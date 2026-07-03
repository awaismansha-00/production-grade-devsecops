output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main_cluster.name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = aws_eks_cluster.main_cluster.endpoint
}

output "vpc_id" {
  value       = aws_vpc.main.id
  description = "The ID of the VPC"
}
