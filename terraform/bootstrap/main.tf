###############################################################################
# Bootstrap: prerequisites the main pipeline cannot create for itself.
#
#   1. S3 bucket + DynamoDB table  -> remote state backend
#   2. GitHub OIDC provider        -> keyless CI auth
#   3. IAM deploy role             -> assumed by GitHub Actions
#
# Run once, locally, with admin credentials:
#   cd terraform/bootstrap
#   terraform init
#   terraform apply -var github_owner=<org> -var github_repo=db_migrations
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  partition    = data.aws_partition.current.partition
  bucket_name  = var.state_bucket_name != "" ? var.state_bucket_name : "${var.project}-tfstate-${local.account_id}"
  table_name   = var.lock_table_name != "" ? var.lock_table_name : "${var.project}-tf-locks"
  oidc_host    = "token.actions.githubusercontent.com"
  oidc_arn     = "arn:${local.partition}:iam::${local.account_id}:oidc-provider/${local.oidc_host}"
  role_subject = "repo:${var.github_owner}/${var.github_repo}"
}

###############################################################################
# Remote state backend
###############################################################################

resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "locks" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

###############################################################################
# GitHub OIDC provider
###############################################################################

data "tls_certificate" "github" {
  url = "https://${local.oidc_host}/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://${local.oidc_host}"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

###############################################################################
# Deploy role assumed by GitHub Actions
###############################################################################

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Scope to this repository. Tighten to specific refs/environments for prod.
    condition {
      test     = "StringLike"
      variable = "${local.oidc_host}:sub"
      values   = ["${local.role_subject}:*"]
    }
  }

  depends_on = [aws_iam_openid_connect_provider.github]
}

resource "aws_iam_role" "deploy" {
  name               = "${var.project}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  description        = "Assumed by GitHub Actions to deploy the DB migration stack."
}

# PowerUserAccess covers every non-IAM service this stack touches
# (VPC, EC2, RDS, DMS, SNS, CloudWatch, Logs, S3 state, DynamoDB lock).
resource "aws_iam_role_policy_attachment" "deploy_poweruser" {
  role       = aws_iam_role.deploy.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/PowerUserAccess"
}

# Scoped IAM permissions PowerUserAccess intentionally excludes: just enough to
# manage the roles/instance-profiles this project creates, and pass them.
data "aws_iam_policy_document" "iam_management" {
  statement {
    sid    = "ManageProjectRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:UpdateRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRoleTags",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:ListInstanceProfilesForRole",
      "iam:TagInstanceProfile",
    ]
    resources = [
      "arn:${local.partition}:iam::${local.account_id}:role/dms-vpc-role",
      "arn:${local.partition}:iam::${local.account_id}:role/dms-cloudwatch-logs-role",
      "arn:${local.partition}:iam::${local.account_id}:role/${var.project}-*",
      "arn:${local.partition}:iam::${local.account_id}:instance-profile/${var.project}-*",
    ]
  }

  statement {
    sid     = "PassProjectRoles"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = [
      "arn:${local.partition}:iam::${local.account_id}:role/dms-vpc-role",
      "arn:${local.partition}:iam::${local.account_id}:role/dms-cloudwatch-logs-role",
      "arn:${local.partition}:iam::${local.account_id}:role/${var.project}-*",
    ]
  }

  statement {
    sid       = "ManageDmsServiceLinkedRole"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["dms.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "deploy_iam" {
  name   = "${var.project}-iam-management"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.iam_management.json
}
