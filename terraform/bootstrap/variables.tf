variable "aws_region" {
  description = "Region for the state bucket, lock table, and IAM resources."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name used as a prefix."
  type        = string
  default     = "aws-db-migration"
}

variable "github_owner" {
  description = "GitHub org/user that owns the repository (e.g. your-org)."
  type        = string
  default     = "Parah"
}

variable "github_repo" {
  description = "Repository name (e.g. db_migrations)."
  type        = string
}

variable "state_bucket_name" {
  description = "Globally-unique S3 bucket name for remote state. Empty derives one from the account ID."
  type        = string
  default     = "bathbucket31"
}

variable "lock_table_name" {
  description = "DynamoDB table name for state locking."
  type        = string
  default     = "dyning_table"
}

variable "create_oidc_provider" {
  description = "Create the GitHub OIDC provider. Set false if one already exists in the account."
  type        = bool
  default     = true
}
