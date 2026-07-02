environment = "dev"
aws_region  = "us-east-1"

# Terraform owns the DMS service roles (dms-vpc-role / dms-cloudwatch-logs-role).
# One-time: if the account already has them, remove them first with
# docs/iam/delete-dms-service-roles.sh so Terraform can create them cleanly.
manage_dms_service_roles = true

# --- dev/source DB (public — restrict to YOUR IPs) --------------------------
dev_db_allowed_cidrs        = [] # e.g. ["203.0.113.4/32"] — your office/home IP
source_db_instance_class    = "db.t3.small"
source_db_allocated_storage = 20

# --- prod/target DB (private) -----------------------------------------------
target_db_instance_class      = "db.t3.small"
target_db_allocated_storage   = 20
target_db_multi_az            = false
target_db_deletion_protection = false

# --- bastion + DMS ----------------------------------------------------------
bastion_instance_type          = "t3.micro"
dms_replication_instance_class = "dms.t3.medium"
dms_migration_type             = "full-load-and-cdc"
dms_start_task                 = false
