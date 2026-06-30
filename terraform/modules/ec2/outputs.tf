output "instance_id" {
  description = "ID of the source host."
  value       = aws_instance.source.id
}

output "public_ip" {
  description = "Public IP of the source host."
  value       = aws_instance.source.public_ip
}

output "private_ip" {
  description = "Private IP of the source host (used by the DMS source endpoint)."
  value       = aws_instance.source.private_ip
}

output "ami_id" {
  description = "AMI used for the source host."
  value       = data.aws_ami.ubuntu.id
}
