###############################################################################
# Global / naming
###############################################################################

variable "project" {
  description = "Project name used as a prefix for all resource names."
  type        = string
  default     = "aws-db-migration"
}

variable "environment" {
  description = "Deployment tier (e.g. dev, staging, prod). Each tier is a full source->target pipeline."
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
  description = "CIDR blocks for public subnets (one per AZ). Host the NAT gateway and the public dev/source DB."
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ). Host the prod/target DB, DMS, bastion, and SSM endpoints."
  type        = list(string)
  default     = ["10.20.11.0/24", "10.20.12.0/24"]
}

###############################################################################
# Databases (both Amazon RDS for MySQL)
#
#   source = dev DB   : publicly reachable (SG-locked), where data is loaded
#   target = prod DB  : private, reachable only by DMS + the SSM bastion
###############################################################################

variable "db_name" {
  description = "Application database/schema name."
  type        = string
  default     = "appdb"
}

variable "db_port" {
  description = "MySQL port."
  type        = number
  default     = 3306
}

variable "rds_engine_version" {
  description = "RDS MySQL engine version (both databases)."
  type        = string
  default     = "8.0"
}

variable "rds_admin_user" {
  description = "Master username for both RDS instances."
  type        = string
  default     = "admin"
}

variable "rds_admin_password" {
  description = "Master password for both RDS instances. Provide via TF_VAR / CI secret."
  type        = string
  sensitive   = true
}

# --- source / dev DB ---------------------------------------------------------

variable "dev_db_allowed_cidrs" {
  description = "CIDR blocks permitted to reach the public dev/source DB (your office/home IPs). Empty = no public ingress."
  type        = list(string)
  default     = []
}

variable "source_db_instance_class" {
  description = "Instance class for the dev/source DB."
  type        = string
  default     = "db.t3.small"
}

variable "source_db_allocated_storage" {
  description = "Allocated storage (GiB) for the dev/source DB."
  type        = number
  default     = 20
}

# --- target / prod DB --------------------------------------------------------

variable "target_db_instance_class" {
  description = "Instance class for the prod/target DB."
  type        = string
  default     = "db.t3.small"
}

variable "target_db_allocated_storage" {
  description = "Allocated storage (GiB) for the prod/target DB."
  type        = number
  default     = 20
}

variable "target_db_multi_az" {
  description = "Multi-AZ for the prod/target DB."
  type        = bool
  default     = false
}

variable "target_db_deletion_protection" {
  description = "Deletion protection for the prod/target DB."
  type        = bool
  default     = false
}

# --- DMS replication user (created on the source DB via scripts/setup_source_db.sql)

variable "dms_db_user" {
  description = "MySQL user DMS uses to read the source DB (needs REPLICATION privileges)."
  type        = string
  default     = "dms_user"
}

variable "dms_db_password" {
  description = "Password for the DMS source user. Provide via TF_VAR / CI secret."
  type        = string
  sensitive   = true
}

###############################################################################
# SSM bastion (jump host for reaching the private prod/target DB over SSM)
###############################################################################

variable "bastion_instance_type" {
  description = "Instance type for the SSM bastion."
  type        = string
  default     = "t3.micro"
}

variable "bastion_root_volume_size" {
  description = "Root volume size (GiB) for the bastion."
  type        = number
  default     = 10
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
  description = "Whether Terraform should start the replication task on creation (normally started via the Migrate flow)."
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
