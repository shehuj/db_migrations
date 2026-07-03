output "vpc_id" {
  description = "ID of the VPC."
  value       = module.networking.vpc_id
}

output "dev_db_endpoint" {
  description = "Connection endpoint of the dev DB (public — developers connect here directly)."
  value       = module.rds_dev.endpoint
}

output "dev_db_address" {
  description = "Hostname of the dev DB."
  value       = module.rds_dev.address
}

output "prod_db_address" {
  description = "Hostname of the prod DB (private — reach via the SSM bastion)."
  value       = module.rds_prod.address
}

output "bastion_instance_id" {
  description = "SSM bastion instance ID (target for `aws ssm start-session`)."
  value       = module.ec2.instance_id
}

output "sns_alarm_topic_arn" {
  description = "ARN of the SNS topic alarms publish to."
  value       = module.monitoring.sns_topic_arn
}
