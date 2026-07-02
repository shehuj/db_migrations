###############################################################################
# Root composition
#
# One source->target pipeline:
#
#   networking ─┬─> rds.source  (dev DB, public, SG-locked)
#               ├─> rds.target  (prod DB, private)
#               ├─> ec2         (SSM bastion -> reaches prod DB)
#               └─> dms         (replicates source -> target)
#   iam ────────────> ec2 / dms
#   monitoring <──── rds.target / dms / ec2
###############################################################################

module "networking" {
  source = "./modules/networking"

  name_prefix          = local.name_prefix
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  db_port              = var.db_port
  dev_db_allowed_cidrs = var.dev_db_allowed_cidrs
  tags                 = local.common_tags
}

module "iam" {
  source = "./modules/iam"

  name_prefix              = local.name_prefix
  manage_dms_service_roles = var.manage_dms_service_roles
  tags                     = local.common_tags
}

# --- dev DB (source): public, developer-accessible --------------------------

module "rds_source" {
  source = "./modules/rds"

  name_prefix            = local.name_prefix
  role                   = "source"
  subnet_ids             = module.networking.public_subnet_ids
  vpc_security_group_ids = [module.networking.source_db_security_group_id]
  publicly_accessible    = true
  engine_version         = var.rds_engine_version
  instance_class         = var.source_db_instance_class
  allocated_storage      = var.source_db_allocated_storage
  db_name                = var.db_name
  db_port                = var.db_port
  admin_username         = var.rds_admin_user
  admin_password         = var.rds_admin_password
  multi_az               = false
  deletion_protection    = false
  tags                   = local.common_tags
}

# --- prod DB (target): private, SSM/DMS-only --------------------------------

module "rds_target" {
  source = "./modules/rds"

  name_prefix            = local.name_prefix
  role                   = "target"
  subnet_ids             = module.networking.private_subnet_ids
  vpc_security_group_ids = [module.networking.rds_security_group_id]
  publicly_accessible    = false
  engine_version         = var.rds_engine_version
  instance_class         = var.target_db_instance_class
  allocated_storage      = var.target_db_allocated_storage
  db_name                = var.db_name
  db_port                = var.db_port
  admin_username         = var.rds_admin_user
  admin_password         = var.rds_admin_password
  multi_az               = var.target_db_multi_az
  deletion_protection    = var.target_db_deletion_protection
  tags                   = local.common_tags
}

# --- SSM bastion: the only human path to the private prod DB ----------------

module "ec2" {
  source = "./modules/ec2"

  name_prefix          = local.name_prefix
  subnet_id            = module.networking.private_subnet_ids[0]
  security_group_ids   = [module.networking.bastion_security_group_id]
  instance_type        = var.bastion_instance_type
  iam_instance_profile = module.iam.ec2_instance_profile_name
  root_volume_size     = var.bastion_root_volume_size
  tags                 = local.common_tags
}

module "dms" {
  source = "./modules/dms"

  name_prefix                = local.name_prefix
  subnet_ids                 = module.networking.private_subnet_ids
  vpc_security_group_ids     = [module.networking.dms_security_group_id]
  replication_instance_class = var.dms_replication_instance_class
  engine_version             = var.dms_engine_version
  allocated_storage          = var.dms_allocated_storage
  migration_type             = var.dms_migration_type
  start_replication_task     = var.dms_start_task

  source_endpoint = {
    server_name   = module.rds_source.address
    port          = var.db_port
    database_name = var.db_name
    username      = var.dms_db_user
    password      = var.dms_db_password
  }

  target_endpoint = {
    server_name   = module.rds_target.address
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
  rds_instance_id = module.rds_target.instance_id
  tags            = local.common_tags
}
