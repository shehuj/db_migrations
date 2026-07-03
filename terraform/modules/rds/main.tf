###############################################################################
# RDS MySQL instance (used for both the dev DB and the prod DB)
#
#   role = dev  : public (SG-locked to allowed CIDRs) — reachable by developers
#   role = prod : private (no public endpoint)        — reachable only via SSM
#
# The two instances are otherwise identical; the caller varies subnets, security
# groups, public accessibility, and hardening (Multi-AZ, deletion protection).
###############################################################################

locals {
  name = "${var.name_prefix}-${var.role}"
}

resource "aws_db_subnet_group" "this" {
  name       = "${local.name}-subnets"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, { Name = "${local.name}-subnets" })
}

resource "aws_db_instance" "this" {
  identifier     = local.name
  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.allocated_storage * 2
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.admin_username
  password = var.admin_password
  port     = var.db_port

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.vpc_security_group_ids
  multi_az               = var.multi_az
  publicly_accessible    = var.publicly_accessible

  backup_retention_period = 7
  skip_final_snapshot     = true
  deletion_protection     = var.deletion_protection
  apply_immediately       = true

  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]

  tags = merge(var.tags, {
    Name = local.name
    Role = "${var.role}-database"
  })
}
