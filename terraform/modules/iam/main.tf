###############################################################################
# IAM roles
#
# DMS requires three account-level service roles when running in a VPC. AWS
# looks them up by *fixed* names (dms-vpc-role, dms-cloudwatch-logs-role,
# dms-access-for-endpoint), so they are created with those exact names and are
# effectively singletons per account/region.
###############################################################################

data "aws_partition" "current" {}

locals {
  dms_principal = "dms.${data.aws_partition.current.dns_suffix}"
  ec2_principal = "ec2.${data.aws_partition.current.dns_suffix}"
}

data "aws_iam_policy_document" "dms_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = [local.dms_principal]
    }
  }
}

# --- dms-vpc-role : lets DMS manage ENIs in the VPC --------------------------
#
# dms-vpc-role and dms-cloudwatch-logs-role are fixed-name, account-level
# singletons DMS looks up globally. If the account already has them (e.g. from a
# prior DMS console use), set manage_dms_service_roles = false so Terraform does
# not try to recreate them — DMS only needs them to exist, not to be TF-managed.

resource "aws_iam_role" "dms_vpc" {
  count              = var.manage_dms_service_roles ? 1 : 0
  name               = "dms-vpc-role"
  assume_role_policy = data.aws_iam_policy_document.dms_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "dms_vpc" {
  count      = var.manage_dms_service_roles ? 1 : 0
  role       = aws_iam_role.dms_vpc[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}

# --- dms-cloudwatch-logs-role : lets DMS publish task logs -------------------

resource "aws_iam_role" "dms_cloudwatch" {
  count              = var.manage_dms_service_roles ? 1 : 0
  name               = "dms-cloudwatch-logs-role"
  assume_role_policy = data.aws_iam_policy_document.dms_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "dms_cloudwatch" {
  count      = var.manage_dms_service_roles ? 1 : 0
  role       = aws_iam_role.dms_cloudwatch[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonDMSCloudWatchLogsRole"
}

# IAM is eventually consistent. When Terraform creates the DMS service roles in
# the same apply as the replication instance, DMS may validate dms-vpc-role
# before the role/policy has propagated and fail with "not configured properly".
# Wait after the attachments so the roles are visible before DMS uses them.
# (module.dms depends_on module.iam, so this gates the replication instance too.)
resource "time_sleep" "dms_roles_propagation" {
  count = var.manage_dms_service_roles ? 1 : 0

  depends_on = [
    aws_iam_role_policy_attachment.dms_vpc,
    aws_iam_role_policy_attachment.dms_cloudwatch,
  ]

  create_duration = "60s"
}

# --- dms-access-for-endpoint : used by endpoints (e.g. S3/Secrets) -----------

resource "aws_iam_role" "dms_access_for_endpoint" {
  name               = "${var.name_prefix}-dms-access-for-endpoint"
  assume_role_policy = data.aws_iam_policy_document.dms_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "dms_access_for_endpoint" {
  role       = aws_iam_role.dms_access_for_endpoint.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonDMSRedshiftS3Role"
}

###############################################################################
# SSM bastion instance profile
#
# Grants SSM access so the private bastion can be reached without SSH, plus
# CloudWatch agent permissions for metrics/logs.
###############################################################################

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = [local.ec2_principal]
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${var.name_prefix}-bastion-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_cloudwatch" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.name_prefix}-bastion-profile"
  role = aws_iam_role.ec2.name
  tags = var.tags
}
