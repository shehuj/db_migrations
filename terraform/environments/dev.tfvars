environment = "dev"
aws_region  = "us-east-1"

# --- dev DB (public — restrict to developer IPs) ----------------------------
dev_db_allowed_cidrs     = [] # e.g. ["203.0.113.4/32"] — your office/home IPs
dev_db_instance_class    = "db.t3.small"
dev_db_allocated_storage = 20

# --- prod DB (private, SSM-only) --------------------------------------------
prod_db_instance_class      = "db.t3.small"
prod_db_allocated_storage   = 20
prod_db_multi_az            = false
prod_db_deletion_protection = false

# --- bastion ----------------------------------------------------------------
bastion_instance_type = "t3.micro"
