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

output "dev_db_security_group_id" {
  description = "Security group ID for the public dev RDS."
  value       = aws_security_group.dev_db.id
}

output "prod_db_security_group_id" {
  description = "Security group ID for the private prod RDS."
  value       = aws_security_group.prod_db.id
}

output "bastion_security_group_id" {
  description = "Security group ID for the SSM bastion."
  value       = aws_security_group.bastion.id
}
