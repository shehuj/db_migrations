###############################################################################
# AWS Database Migration Service
#
# Components:
#   - replication subnet group (which subnets the instance lives in)
#   - replication instance (the worker)
#   - source endpoint (EC2 MySQL) + target endpoint (RDS MySQL)
#   - replication task (table mappings + settings)
###############################################################################

resource "aws_dms_replication_subnet_group" "this" {
  replication_subnet_group_id          = "${var.name_prefix}-dms-subnets"
  replication_subnet_group_description = "Subnet group for ${var.name_prefix} DMS"
  subnet_ids                           = var.subnet_ids

  tags = merge(var.tags, { Name = "${var.name_prefix}-dms-subnets" })
}

resource "aws_dms_replication_instance" "this" {
  replication_instance_id    = "${var.name_prefix}-dms"
  replication_instance_class = var.replication_instance_class
  allocated_storage          = var.allocated_storage
  # Empty -> omit so AWS uses the current default engine (versions vary by region
  # and get deprecated; pinning a stale one fails with InvalidParameterValue).
  engine_version              = var.engine_version != "" ? var.engine_version : null
  publicly_accessible         = false
  multi_az                    = false
  auto_minor_version_upgrade  = true
  apply_immediately           = true
  vpc_security_group_ids      = var.vpc_security_group_ids
  replication_subnet_group_id = aws_dms_replication_subnet_group.this.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-dms" })
}

###############################################################################
# Endpoints
###############################################################################

resource "aws_dms_endpoint" "source" {
  endpoint_id   = "${var.name_prefix}-source"
  endpoint_type = "source"
  engine_name   = "mysql"

  server_name   = var.source_endpoint.server_name
  port          = var.source_endpoint.port
  database_name = var.source_endpoint.database_name
  username      = var.source_endpoint.username
  password      = var.source_endpoint.password
  ssl_mode      = "none"

  tags = merge(var.tags, { Name = "${var.name_prefix}-source" })
}

resource "aws_dms_endpoint" "target" {
  endpoint_id   = "${var.name_prefix}-target"
  endpoint_type = "target"
  engine_name   = "mysql"

  server_name   = var.target_endpoint.server_name
  port          = var.target_endpoint.port
  database_name = var.target_endpoint.database_name
  username      = var.target_endpoint.username
  password      = var.target_endpoint.password
  ssl_mode      = "none"

  tags = merge(var.tags, { Name = "${var.name_prefix}-target" })
}

###############################################################################
# Replication task
###############################################################################

resource "aws_dms_replication_task" "this" {
  replication_task_id      = "${var.name_prefix}-task"
  migration_type           = var.migration_type
  replication_instance_arn = aws_dms_replication_instance.this.replication_instance_arn
  source_endpoint_arn      = aws_dms_endpoint.source.endpoint_arn
  target_endpoint_arn      = aws_dms_endpoint.target.endpoint_arn

  table_mappings            = file("${path.module}/table_mappings.json")
  replication_task_settings = file("${path.module}/task_settings.json")

  start_replication_task = var.start_replication_task

  tags = merge(var.tags, { Name = "${var.name_prefix}-task" })

  lifecycle {
    ignore_changes = [replication_task_settings]
  }
}
