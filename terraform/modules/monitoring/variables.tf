variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "alarm_email" {
  description = "Email subscribed to the alarm topic. Empty string skips the subscription."
  type        = string
  default     = ""
}

variable "ec2_instance_id" {
  description = "SSM bastion instance ID to monitor."
  type        = string
}

variable "rds_instance_id" {
  description = "Prod RDS instance identifier to monitor."
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
