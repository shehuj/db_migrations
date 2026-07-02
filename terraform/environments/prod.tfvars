environment = "prod"
aws_region  = "us-east-1"

# Set false if this account already has dms-vpc-role / dms-cloudwatch-logs-role.
manage_dms_service_roles = true

# --- dev/source DB (public — restrict to YOUR IPs) --------------------------
dev_db_allowed_cidrs        = [] # lock to your CIDRs
source_db_instance_class    = "db.t3.medium"
source_db_allocated_storage = 50

# --- prod/target DB (private, hardened) -------------------------------------
target_db_instance_class      = "db.r6g.large"
target_db_allocated_storage   = 100
target_db_multi_az            = true
target_db_deletion_protection = true

# --- bastion + DMS ----------------------------------------------------------
bastion_instance_type          = "t3.micro"
dms_replication_instance_class = "dms.c5.large"
dms_migration_type             = "full-load-and-cdc"
dms_start_task                 = false
