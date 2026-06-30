output "vpc_id" {
  description = "ID of the VPC."
  value       = module.networking.vpc_id
}

output "source_ec2_public_ip" {
  description = "Public IP of the source MySQL host (used by Ansible)."
  value       = module.ec2.public_ip
}

output "source_ec2_private_ip" {
  description = "Private IP of the source MySQL host (used by DMS source endpoint)."
  value       = module.ec2.private_ip
}

output "rds_endpoint" {
  description = "Connection endpoint of the target RDS instance."
  value       = module.rds.endpoint
}

output "rds_address" {
  description = "Hostname of the target RDS instance."
  value       = module.rds.address
}

output "dms_replication_instance_arn" {
  description = "ARN of the DMS replication instance."
  value       = module.dms.replication_instance_arn
}

output "dms_replication_task_arn" {
  description = "ARN of the DMS replication task."
  value       = module.dms.replication_task_arn
}

output "sns_alarm_topic_arn" {
  description = "ARN of the SNS topic alarms publish to."
  value       = module.monitoring.sns_topic_arn
}
