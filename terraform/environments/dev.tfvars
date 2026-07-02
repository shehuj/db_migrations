environment       = "dev"
aws_region        = "us-east-1"
ec2_instance_type = "t3.small"

# Source host is private + SSM-only; Ansible transfers files via this S3 bucket.
ssm_transfer_bucket = "bathbucket31"

# Terraform owns the DMS service roles (dms-vpc-role / dms-cloudwatch-logs-role).
# One-time: if the account already has them, remove them first with
# docs/iam/delete-dms-service-roles.sh so Terraform can create them cleanly.
manage_dms_service_roles = true

rds_instance_class      = "db.t3.small"
rds_multi_az            = false
rds_deletion_protection = false

dms_replication_instance_class = "dms.t3.medium"
dms_migration_type             = "full-load-and-cdc"
dms_start_task                 = false
