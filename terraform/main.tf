###############################################################################
# Root composition
#
# Wires together the single-responsibility modules. The dependency flow is:
#
#   networking ─┬─> ec2   (source MySQL host)
#               ├─> rds   (target database)
#               └─> dms   (replication instance + endpoints + task)
#   iam ────────────> ec2 / dms
#   monitoring <──── rds / dms / ec2
###############################################################################

module "networking" {
  source = "./modules/networking"

  name_prefix          = local.name_prefix
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  allowed_ssh_cidrs    = var.allowed_ssh_cidrs
  db_port              = var.db_port
  tags                 = local.common_tags
}

module "iam" {
  source = "./modules/iam"

  name_prefix              = local.name_prefix
  manage_dms_service_roles = var.manage_dms_service_roles
  tags                     = local.common_tags
}

module "ec2" {
  source = "./modules/ec2"

  name_prefix          = local.name_prefix
  subnet_id            = module.networking.public_subnet_ids[0]
  security_group_ids   = [module.networking.source_db_security_group_id]
  instance_type        = var.ec2_instance_type
  key_name             = var.key_name
  iam_instance_profile = module.iam.ec2_instance_profile_name
  root_volume_size     = var.ec2_root_volume_size
  tags                 = local.common_tags
}

module "rds" {
  source = "./modules/rds"

  name_prefix            = local.name_prefix
  subnet_ids             = module.networking.private_subnet_ids
  vpc_security_group_ids = [module.networking.rds_security_group_id]
  engine_version         = var.rds_engine_version
  instance_class         = var.rds_instance_class
  allocated_storage      = var.rds_allocated_storage
  db_name                = var.db_name
  db_port                = var.db_port
  admin_username         = var.rds_admin_user
  admin_password         = var.rds_admin_password
  multi_az               = var.rds_multi_az
  deletion_protection    = var.rds_deletion_protection
  tags                   = local.common_tags
}

module "dms" {
  source = "./modules/dms"

  name_prefix                = local.name_prefix
  subnet_ids                 = module.networking.private_subnet_ids
  vpc_security_group_ids     = [module.networking.dms_security_group_id]
  replication_instance_class = var.dms_replication_instance_class
  allocated_storage          = var.dms_allocated_storage
  migration_type             = var.dms_migration_type
  start_replication_task     = var.dms_start_task

  source_endpoint = {
    server_name   = module.ec2.private_ip
    port          = var.db_port
    database_name = var.db_name
    username      = var.dms_db_user
    password      = var.dms_db_password
  }

  target_endpoint = {
    server_name   = module.rds.address
    port          = var.db_port
    database_name = var.db_name
    username      = var.rds_admin_user
    password      = var.rds_admin_password
  }

  tags = local.common_tags

  # DMS in a VPC requires the account-level dms-vpc-role / dms-cloudwatch-logs-role
  # (created by the iam module) to exist before the replication subnet group.
  depends_on = [module.iam]
}

module "monitoring" {
  source = "./modules/monitoring"

  name_prefix     = local.name_prefix
  alarm_email     = var.alarm_email
  ec2_instance_id = module.ec2.instance_id
  rds_instance_id = module.rds.instance_id
  tags            = local.common_tags
}
