###############################################################################
# Root composition
#
# Two independent Amazon RDS for MySQL databases + an SSM bastion:
#
#   networking ─┬─> rds.dev   (public, SG-locked — all developers connect here)
#               ├─> rds.prod  (private — reachable only via the SSM bastion)
#               └─> ec2       (SSM bastion — the sole human path to the prod DB)
#   iam ────────────> ec2
#   monitoring <──── rds.prod / ec2
#
# Terraform provisions the infrastructure only. Ansible (ansible/) configures
# and seeds each database: dev directly, prod through the SSM port-forward.
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

  name_prefix = local.name_prefix
  tags        = local.common_tags
}

# --- dev DB: public, developer-accessible -----------------------------------

module "rds_dev" {
  source = "./modules/rds"

  name_prefix            = local.name_prefix
  role                   = "dev"
  subnet_ids             = module.networking.public_subnet_ids
  vpc_security_group_ids = [module.networking.dev_db_security_group_id]
  publicly_accessible    = true
  engine_version         = var.rds_engine_version
  instance_class         = var.dev_db_instance_class
  allocated_storage      = var.dev_db_allocated_storage
  db_name                = var.db_name
  db_port                = var.db_port
  admin_username         = var.rds_admin_user
  admin_password         = var.rds_admin_password
  multi_az               = false
  deletion_protection    = false
  tags                   = local.common_tags
}

# --- prod DB: private, SSM-only ---------------------------------------------

module "rds_prod" {
  source = "./modules/rds"

  name_prefix            = local.name_prefix
  role                   = "prod"
  subnet_ids             = module.networking.private_subnet_ids
  vpc_security_group_ids = [module.networking.prod_db_security_group_id]
  publicly_accessible    = false
  engine_version         = var.rds_engine_version
  instance_class         = var.prod_db_instance_class
  allocated_storage      = var.prod_db_allocated_storage
  db_name                = var.db_name
  db_port                = var.db_port
  admin_username         = var.rds_admin_user
  admin_password         = var.rds_admin_password
  multi_az               = var.prod_db_multi_az
  deletion_protection    = var.prod_db_deletion_protection
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

module "monitoring" {
  source = "./modules/monitoring"

  name_prefix     = local.name_prefix
  alarm_email     = var.alarm_email
  ec2_instance_id = module.ec2.instance_id
  rds_instance_id = module.rds_prod.instance_id
  tags            = local.common_tags
}
