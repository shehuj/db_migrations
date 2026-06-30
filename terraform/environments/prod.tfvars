environment       = "prod"
aws_region        = "us-east-1"
ec2_instance_type = "t3.large"

allowed_ssh_cidrs = [] # rely on SSM, no public SSH in prod

rds_instance_class      = "db.r6g.large"
rds_allocated_storage   = 100
rds_multi_az            = true
rds_deletion_protection = true

dms_replication_instance_class = "dms.c5.large"
dms_migration_type             = "full-load-and-cdc"
dms_start_task                 = false
