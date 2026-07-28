output "address" {
  description = "RDS instance address"
  value       = aws_db_instance.this.address
}

output "endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.this.endpoint
}

output "port" {
  description = "RDS MySQL port"
  value       = aws_db_instance.this.port
}

output "security_group_id" {
  description = "RDS security group ID"
  value       = aws_security_group.this.id
}

output "identifier" {
  description = "RDS instance identifier"
  value       = aws_db_instance.this.identifier
}