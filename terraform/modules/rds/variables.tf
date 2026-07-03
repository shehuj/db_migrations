variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "role" {
  description = "Logical role of this instance: dev or prod. Used in resource names and tags."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.role)
    error_message = "role must be dev or prod."
  }
}

variable "subnet_ids" {
  description = "Subnet IDs for the DB subnet group (public for dev, private for prod)."
  type        = list(string)
}

variable "vpc_security_group_ids" {
  description = "Security group IDs to attach to the instance."
  type        = list(string)
}

variable "publicly_accessible" {
  description = "Whether the instance gets a public endpoint."
  type        = bool
  default     = false
}

variable "engine_version" {
  description = "MySQL engine version."
  type        = string
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
}

variable "allocated_storage" {
  description = "Allocated storage in GiB."
  type        = number
}

variable "db_name" {
  description = "Initial database name."
  type        = string
}

variable "db_port" {
  description = "MySQL port."
  type        = number
}

variable "admin_username" {
  description = "Master username."
  type        = string
}

variable "admin_password" {
  description = "Master password."
  type        = string
  sensitive   = true
}

variable "multi_az" {
  description = "Enable Multi-AZ."
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Enable deletion protection."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
