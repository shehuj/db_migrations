variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "ssm_transfer_bucket" {
  description = "Existing S3 bucket the EC2 role may use for aws_ssm file transfer."
  type        = string
}

variable "manage_dms_service_roles" {
  description = "Create the account-singleton dms-vpc-role / dms-cloudwatch-logs-role. Set false if they already exist in the account."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
