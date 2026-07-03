output "s3_bucket_name" {
  value = aws_s3_bucket.terraform_state_bucket.id
  description = "Name of the s3 bucket which contains terraform state file"
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.terraform_state_lock.name
  description = "Name of the dynamodb table which is used for terraform state locking"
}