output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "The ID of the VPC"
}

output "nodejs_app_ecr_repository_url" {
  description = "ECR repository URL for the Node.js app image"
  value       = module.ecr.repository_url
}

output "cluster_security_group_id" {
  description = "EKS cluster security group ID"
  value       = module.eks.cluster_security_group_id
}
output "rds_mysql_address" {
  description = "RDS MySQL address"
  value       = module.rds_mysql.address
}

output "ssm_tunnel_instance_id" {
  description = "SSM tunnel host instance ID"
  value       = module.ssm_tunnel_host.instance_id
}

output "github_actions_ecr_role_arn" {
  description = "IAM role ARN used by GitHub Actions for ECR"
  value       = module.github_actions_ecr_role.role_arn
}