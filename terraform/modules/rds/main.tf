###############################################################################
# RDS MySQL instance (used for both the source/dev DB and the target/prod DB)
###############################################################################

locals {
  name = "${var.name_prefix}-${var.role}"
}

resource "aws_db_subnet_group" "this" {
  name       = "${local.name}-subnets"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, { Name = "${local.name}-subnets" })
}

# ROW-based binlog is required so this instance can act as a DMS *source*.
# It is harmless on the target, so both instances get it.
resource "aws_db_parameter_group" "this" {
  name        = "${local.name}-mysql8"
  family      = "mysql8.0"
  description = "Parameter group for ${local.name}"

  parameter {
    name  = "binlog_format"
    value = "ROW"
  }

  parameter {
    name  = "binlog_row_image"
    value = "FULL"
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
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
  parameter_group_name   = aws_db_parameter_group.this.name
  multi_az               = var.multi_az
  publicly_accessible    = var.publicly_accessible

  # Backups must be enabled for a MySQL instance to serve as a DMS/CDC source.
  backup_retention_period = 7
  skip_final_snapshot     = true
  deletion_protection     = var.deletion_protection
  apply_immediately       = true

  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]

  tags = merge(var.tags, {
    Name = local.name
    Role = var.role == "source" ? "dev-database" : "prod-database"
  })
}
