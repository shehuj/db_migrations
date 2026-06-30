output "deploy_role_arn" {
  description = "Set this as the repo secret AWS_ROLE_ARN."
  value       = aws_iam_role.deploy.arn
}

output "state_bucket" {
  description = "Set this as the repo secret TF_BACKEND_BUCKET."
  value       = aws_s3_bucket.state.bucket
}

output "lock_table" {
  description = "Set this as the repo secret TF_BACKEND_TABLE."
  value       = aws_dynamodb_table.locks.name
}

output "region" {
  description = "Region the backend lives in (set repo variable AWS_REGION to match)."
  value       = var.aws_region
}

output "gh_cli_commands" {
  description = "Copy/paste to push these values into the repo with the gh CLI."
  value       = <<-EOT
    gh secret set AWS_ROLE_ARN       --body "${aws_iam_role.deploy.arn}"
    gh secret set TF_BACKEND_BUCKET  --body "${aws_s3_bucket.state.bucket}"
    gh secret set TF_BACKEND_TABLE   --body "${aws_dynamodb_table.locks.name}"
    gh variable set AWS_REGION       --body "${var.aws_region}"
    # Then add the database password secrets:
    # gh secret set DMS_DB_PASSWORD       --body "<choose-a-strong-password>"
    # gh secret set RDS_ADMIN_PASSWORD    --body "<choose-a-strong-password>"
    # gh secret set SOURCE_DB_ADMIN_PASSWORD --body "<choose-a-strong-password>"
    # gh secret set SSH_PRIVATE_KEY    < path/to/keypair.pem
  EOT
}
