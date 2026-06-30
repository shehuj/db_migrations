variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the replication subnet group."
  type        = list(string)
}

variable "vpc_security_group_ids" {
  description = "Security group IDs for the replication instance."
  type        = list(string)
}

variable "replication_instance_class" {
  description = "DMS replication instance class."
  type        = string
}

variable "allocated_storage" {
  description = "Storage in GiB for the replication instance."
  type        = number
}

variable "migration_type" {
  description = "full-load, cdc, or full-load-and-cdc."
  type        = string
}

variable "start_replication_task" {
  description = "Whether to start the task on creation."
  type        = bool
  default     = false
}

variable "source_endpoint" {
  description = "Source (EC2 MySQL) connection details."
  type = object({
    server_name   = string
    port          = number
    database_name = string
    username      = string
    password      = string
  })
  sensitive = true
}

variable "target_endpoint" {
  description = "Target (RDS MySQL) connection details."
  type = object({
    server_name   = string
    port          = number
    database_name = string
    username      = string
    password      = string
  })
  sensitive = true
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
