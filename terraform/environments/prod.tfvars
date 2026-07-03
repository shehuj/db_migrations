environment = "prod"
aws_region  = "us-east-1"

# --- dev DB (public — restrict to developer IPs) ----------------------------
dev_db_allowed_cidrs     = [] # lock to your CIDRs
dev_db_instance_class    = "db.t3.medium"
dev_db_allocated_storage = 50

# --- prod DB (private, SSM-only, hardened) ----------------------------------
prod_db_instance_class      = "db.r6g.large"
prod_db_allocated_storage   = 100
prod_db_multi_az            = true
prod_db_deletion_protection = true

# --- bastion ----------------------------------------------------------------
bastion_instance_type = "t3.micro"
