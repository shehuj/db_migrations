environment       = "dev"
aws_region        = "us-east-1"
ec2_instance_type = "t3.small"

rds_instance_class      = "db.t3.small"
rds_multi_az            = false
rds_deletion_protection = false

dms_replication_instance_class = "dms.t3.medium"
dms_migration_type             = "full-load-and-cdc"
dms_start_task                 = false
