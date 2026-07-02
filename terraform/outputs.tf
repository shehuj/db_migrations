output "vpc_id" {
  description = "ID of the VPC."
  value       = module.networking.vpc_id
}

output "source_ec2_instance_id" {
  description = "Instance ID of the source MySQL host (used by Ansible over SSM)."
  value       = module.ec2.instance_id
}

output "source_ec2_private_ip" {
  description = "Private IP of the source MySQL host (used by DMS source endpoint)."
  value       = module.ec2.private_ip
}

output "ssm_transfer_bucket" {
  description = "S3 bucket Ansible's aws_ssm connection uses for file transfer."
  value       = var.ssm_transfer_bucket
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
