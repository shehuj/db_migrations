output "instance_id" {
  description = "ID of the SSM bastion (target for `aws ssm start-session`)."
  value       = aws_instance.bastion.id
}

output "ami_id" {
  description = "AMI used for the bastion."
  value       = data.aws_ami.ubuntu.id
}
