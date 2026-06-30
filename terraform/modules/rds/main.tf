###############################################################################
# Target RDS MySQL instance
###############################################################################

resource "aws_db_subnet_group" "this" {
  name       = "${var.name_prefix}-rds-subnets"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, { Name = "${var.name_prefix}-rds-subnets" })
}

# Parameter group: enforce ROW-based binlog on the target as well, so the RDS
# instance can itself act as a replication source later if needed.
resource "aws_db_parameter_group" "this" {
  name        = "${var.name_prefix}-mysql8"
  family      = "mysql8.0"
  description = "Parameter group for ${var.name_prefix} target MySQL"

  parameter {
    name  = "binlog_format"
    value = "ROW"
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name_prefix}-target"
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
  publicly_accessible    = false

  backup_retention_period = 7
  skip_final_snapshot     = true
  deletion_protection     = var.deletion_protection
  apply_immediately       = true

  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-target"
    Role = "target-database"
  })
}
