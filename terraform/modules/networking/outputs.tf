output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets."
  value       = aws_subnet.private[*].id
}

output "source_db_security_group_id" {
  description = "Security group ID for the dev/source RDS."
  value       = aws_security_group.source_db.id
}

output "rds_security_group_id" {
  description = "Security group ID for the prod/target RDS."
  value       = aws_security_group.rds.id
}

output "dms_security_group_id" {
  description = "Security group ID for the DMS replication instance."
  value       = aws_security_group.dms.id
}

output "bastion_security_group_id" {
  description = "Security group ID for the SSM bastion."
  value       = aws_security_group.bastion.id
}
