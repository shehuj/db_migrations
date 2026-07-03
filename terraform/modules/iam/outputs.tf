output "ec2_instance_profile_name" {
  description = "Name of the EC2 instance profile for the SSM bastion."
  value       = aws_iam_instance_profile.ec2.name
}
