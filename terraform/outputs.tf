output "vpc_id" {
  description = "ID of the VPC."
  value       = module.networking.vpc_id
}

output "dev_db_endpoint" {
  description = "Connection endpoint of the dev/source DB (public — devs load data here)."
  value       = module.rds_source.endpoint
}

output "dev_db_address" {
  description = "Hostname of the dev/source DB."
  value       = module.rds_source.address
}

output "prod_db_address" {
  description = "Hostname of the prod/target DB (private — reach via the SSM bastion)."
  value       = module.rds_target.address
}

output "bastion_instance_id" {
  description = "SSM bastion instance ID (target for `aws ssm start-session`)."
  value       = module.ec2.instance_id
}

output "dms_replication_task_arn" {
  description = "ARN of the DMS replication task (dev -> prod)."
  value       = module.dms.replication_task_arn
}

output "sns_alarm_topic_arn" {
  description = "ARN of the SNS topic alarms publish to."
  value       = module.monitoring.sns_topic_arn
}
