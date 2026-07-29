output "s3_bucket_name" {
  value       = aws_s3_bucket.terraform_state_bucket.id
  description = "Name of the s3 bucket which contains terraform state file"
}
