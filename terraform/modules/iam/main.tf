###############################################################################
# IAM: SSM bastion instance profile
#
# Grants the private bastion SSM access (so it can be reached without SSH) plus
# CloudWatch agent permissions for metrics/logs. No database credentials live
# here — those flow to Ansible via environment/CI secrets.
###############################################################################

data "aws_partition" "current" {}

locals {
  ec2_principal = "ec2.${data.aws_partition.current.dns_suffix}"
}

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
