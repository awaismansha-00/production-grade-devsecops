provider "aws" {
  region = "eu-west-2"
}

resource "aws_s3_bucket" "terraform_state_bucket" {
  bucket = "production-grade-devsecops-state-bucket"
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = "MyBucket"
    Environment = "Dev"
  }
}

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.terraform_state_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sse" {
  bucket = aws_s3_bucket.terraform_state_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
