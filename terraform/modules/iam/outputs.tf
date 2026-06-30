output "dms_vpc_role_arn" {
  description = "ARN of the dms-vpc-role."
  value       = aws_iam_role.dms_vpc.arn
}

output "dms_cloudwatch_role_arn" {
  description = "ARN of the dms-cloudwatch-logs-role."
  value       = aws_iam_role.dms_cloudwatch.arn
}

output "dms_access_for_endpoint_role_arn" {
  description = "ARN of the DMS endpoint access role."
  value       = aws_iam_role.dms_access_for_endpoint.arn
}

output "ec2_instance_profile_name" {
  description = "Name of the EC2 instance profile for the source host."
  value       = aws_iam_instance_profile.ec2.name
}
