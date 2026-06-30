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

resource "aws_iam_role" "dms_vpc" {
  name               = "dms-vpc-role"
  assume_role_policy = data.aws_iam_policy_document.dms_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "dms_vpc" {
  role       = aws_iam_role.dms_vpc.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}

# --- dms-cloudwatch-logs-role : lets DMS publish task logs -------------------

resource "aws_iam_role" "dms_cloudwatch" {
  name               = "dms-cloudwatch-logs-role"
  assume_role_policy = data.aws_iam_policy_document.dms_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "dms_cloudwatch" {
  role       = aws_iam_role.dms_cloudwatch.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonDMSCloudWatchLogsRole"
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
# EC2 instance profile (source host)
#
# Grants SSM access so the host can be managed/inventoried without an open SSH
# port, plus CloudWatch agent permissions for metrics/logs.
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
  name               = "${var.name_prefix}-source-ec2-role"
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
  name = "${var.name_prefix}-source-ec2-profile"
  role = aws_iam_role.ec2.name
  tags = var.tags
}
