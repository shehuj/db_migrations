environment       = "prod"
aws_region        = "us-east-1"
ec2_instance_type = "t3.large"

# Source host is private + SSM-only; Ansible transfers files via this S3 bucket.
ssm_transfer_bucket = "bathbucket31"

# Set false if this account already has dms-vpc-role / dms-cloudwatch-logs-role.
manage_dms_service_roles = true

rds_instance_class      = "db.r6g.large"
rds_allocated_storage   = 100
rds_multi_az            = true
rds_deletion_protection = true

dms_replication_instance_class = "dms.c5.large"
dms_migration_type             = "full-load-and-cdc"
dms_start_task                 = false
