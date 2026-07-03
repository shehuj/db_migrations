###############################################################################
# Global / naming
###############################################################################

variable "project" {
  description = "Project name used as a prefix for all resource names."
  type        = string
  default     = "aws-db-migration"
}

variable "environment" {
  description = "Deployment tier (e.g. dev, staging, prod). Each tier is a full dev-DB + prod-DB stack."
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

###############################################################################
# Networking
###############################################################################

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  description = "AZs to spread subnets across. At least two are required for RDS subnet groups."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "Provide at least two availability zones."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ). Host the NAT gateway and the public dev DB."
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ). Host the prod DB, bastion, and SSM endpoints."
  type        = list(string)
  default     = ["10.20.11.0/24", "10.20.12.0/24"]
}

###############################################################################
# Databases (both Amazon RDS for MySQL)
#
#   dev  : publicly reachable (SG-locked) — all developers connect directly
#   prod : private, reachable only through the SSM bastion
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

# --- dev DB ------------------------------------------------------------------

variable "dev_db_allowed_cidrs" {
  description = "CIDR blocks permitted to reach the public dev DB (developer office/home IPs). Empty = no public ingress."
  type        = list(string)
  default     = []
}

variable "dev_db_instance_class" {
  description = "Instance class for the dev DB."
  type        = string
  default     = "db.t3.small"
}

variable "dev_db_allocated_storage" {
  description = "Allocated storage (GiB) for the dev DB."
  type        = number
  default     = 20
}

# --- prod DB -----------------------------------------------------------------

variable "prod_db_instance_class" {
  description = "Instance class for the prod DB."
  type        = string
  default     = "db.t3.small"
}

variable "prod_db_allocated_storage" {
  description = "Allocated storage (GiB) for the prod DB."
  type        = number
  default     = 20
}

variable "prod_db_multi_az" {
  description = "Multi-AZ for the prod DB."
  type        = bool
  default     = false
}

variable "prod_db_deletion_protection" {
  description = "Deletion protection for the prod DB. Cleared by the teardown/destroy flow before deleting."
  type        = bool
  default     = false
}

###############################################################################
# SSM bastion (jump host for reaching the private prod DB over SSM)
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
# Monitoring
###############################################################################

variable "alarm_email" {
  description = "Email address subscribed to the CloudWatch alarm SNS topic. Empty disables the subscription."
  type        = string
  default     = ""
}
