variable "name_prefix" {
  description = "Prefix used for IAM resources"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository in owner/name format"
  type        = string
}

variable "branches" {
  description = "Branches allowed to assume the role"
  type        = list(string)
}

variable "ecr_repository_arn" {
  description = "ECR repository ARN"
  type        = string
}