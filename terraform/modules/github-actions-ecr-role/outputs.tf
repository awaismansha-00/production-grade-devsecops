output "role_arn" {
  description = "IAM role ARN for GitHub Actions ECR access"
  value       = aws_iam_role.this.arn
}