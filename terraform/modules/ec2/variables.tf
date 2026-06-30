variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "subnet_id" {
  description = "Public subnet to launch the source host into."
  type        = string
}

variable "security_group_ids" {
  description = "Security group IDs to attach."
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
}

variable "key_name" {
  description = "EC2 key pair name. Empty string disables SSH key association."
  type        = string
  default     = ""
}

variable "iam_instance_profile" {
  description = "IAM instance profile name."
  type        = string
}

variable "root_volume_size" {
  description = "Root volume size in GiB."
  type        = number
  default     = 20
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
