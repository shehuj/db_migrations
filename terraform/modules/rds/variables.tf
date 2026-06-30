variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the DB subnet group."
  type        = list(string)
}

variable "vpc_security_group_ids" {
  description = "Security group IDs to attach to the instance."
  type        = list(string)
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
