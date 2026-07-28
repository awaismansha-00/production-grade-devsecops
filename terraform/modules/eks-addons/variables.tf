variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID used by the AWS Load Balancer Controller"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID used in IAM policy ARNs"
  type        = string
}

variable "external_secret_arns" {
  description = "Secrets Manager ARNs External Secrets Operator can read"
  type        = list(string)
}

variable "aws_lbc_service_account_name" {
  description = "AWS Load Balancer Controller Kubernetes service account name"
  type        = string
  default     = "aws-load-balancer-controller"
}

variable "external_secrets_service_account_name" {
  description = "External Secrets Operator Kubernetes service account name"
  type        = string
  default     = "external-secrets"
}