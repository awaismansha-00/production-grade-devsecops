output "instance_id" {
  description = "SSM tunnel host instance ID"
  value       = aws_instance.this.id
}

output "security_group_id" {
  description = "SSM tunnel host security group ID"
  value       = aws_security_group.this.id
}