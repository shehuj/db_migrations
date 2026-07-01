###############################################################################
# Global / naming
###############################################################################

variable "project" {
  description = "Project name used as a prefix for all resource names."
  type        = string
  default     = "aws-db-migration"
}

variable "environment" {
  description = "Deployment environment (e.g. dev, staging, prod)."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "additional_tags" {
  description = "Extra tags merged into the default tag set."
  type        = map(string)
  default     = {}
}

variable "manage_dms_service_roles" {
  description = "Create the account-singleton dms-vpc-role / dms-cloudwatch-logs-role. Set false if they already exist in the account."
  type        = bool
  default     = true
}

###############################################################################
# Networking
###############################################################################

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  description = "AZs to spread subnets across. At least two are required for RDS/DMS subnet groups."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "Provide at least two availability zones."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ). Hosts the source EC2 MySQL host."
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ). Hosts RDS and the DMS replication instance."
  type        = list(string)
  default     = ["10.20.11.0/24", "10.20.12.0/24"]
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks permitted to SSH to the source EC2 host. Lock this down in production."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

###############################################################################
# Source EC2 (self-managed MySQL)
###############################################################################

variable "ec2_instance_type" {
  description = "Instance type for the source MySQL host."
  type        = string
  default     = "t3.small"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair for SSH/Ansible access. Leave empty to disable SSH key auth."
  type        = string
  default     = ""
}

variable "ec2_root_volume_size" {
  description = "Root EBS volume size (GiB) for the source host."
  type        = number
  default     = 20
}

###############################################################################
# Database credentials (source + target share schema/user for the demo)
###############################################################################

variable "db_name" {
  description = "Application database/schema name to migrate."
  type        = string
  default     = "appdb"
}

variable "db_port" {
  description = "MySQL port."
  type        = number
  default     = 3306
}

# NOTE: the source MySQL *admin* user/password are not Terraform-managed — that
# account is created by the Ansible mysql_source role. Terraform only needs the
# dedicated DMS replication credentials below for the DMS source endpoint.

variable "dms_db_user" {
  description = "Dedicated MySQL user DMS uses to read the source (needs REPLICATION privileges)."
  type        = string
  default     = "dms_user"
}

variable "dms_db_password" {
  description = "Password for the DMS source user. Provide via TF_VAR / CI secret."
  type        = string
  sensitive   = true
}

###############################################################################
# Target RDS
###############################################################################

variable "rds_engine_version" {
  description = "RDS MySQL engine version."
  type        = string
  default     = "8.0"
}

variable "rds_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.small"
}

variable "rds_allocated_storage" {
  description = "RDS allocated storage in GiB."
  type        = number
  default     = 20
}

variable "rds_admin_user" {
  description = "Master username for the target RDS instance."
  type        = string
  default     = "admin"
}

variable "rds_admin_password" {
  description = "Master password for the target RDS instance. Provide via TF_VAR / CI secret."
  type        = string
  sensitive   = true
}

variable "rds_multi_az" {
  description = "Whether the target RDS instance is Multi-AZ."
  type        = bool
  default     = false
}

variable "rds_deletion_protection" {
  description = "Enable deletion protection on the target RDS instance."
  type        = bool
  default     = false
}

###############################################################################
# DMS
###############################################################################

variable "dms_replication_instance_class" {
  description = "DMS replication instance class."
  type        = string
  default     = "dms.t3.medium"
}

variable "dms_engine_version" {
  description = "DMS replication engine version. Empty lets AWS choose the current default (recommended)."
  type        = string
  default     = ""
}

variable "dms_allocated_storage" {
  description = "Storage (GiB) allocated to the DMS replication instance."
  type        = number
  default     = 50
}

variable "dms_migration_type" {
  description = "DMS migration type: full-load, cdc, or full-load-and-cdc."
  type        = string
  default     = "full-load-and-cdc"

  validation {
    condition     = contains(["full-load", "cdc", "full-load-and-cdc"], var.dms_migration_type)
    error_message = "dms_migration_type must be full-load, cdc, or full-load-and-cdc."
  }
}

variable "dms_start_task" {
  description = "Whether Terraform should start the replication task on creation."
  type        = bool
  default     = false
}

###############################################################################
# Monitoring
###############################################################################

variable "alarm_email" {
  description = "Email address subscribed to the CloudWatch alarm SNS topic. Empty disables the subscription."
  type        = string
  default     = ""
}
