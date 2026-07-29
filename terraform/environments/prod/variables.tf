variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-2"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones for the VPC"
  type        = list(string)
  default     = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]
}

variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
}

variable "enable_nat_gateway" {
  description = "Create NAT gateways for private subnet egress. Disable when Elastic IP allocation is blocked."
  type        = bool
  default     = false
}

variable "eks_nodes_in_public_subnets" {
  description = "Place EKS managed nodes in public subnets for no-NAT first-run deployments."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "production-grade-devsecops-cluster"
}

variable "cluster_version" {
  description = "Version of the EKS cluster"
  type        = string
  default     = "1.36"
}

variable "node_groups" {
  description = "EKS node group configuration"
  type = map(object({
    instance_types = list(string)
    capacity_type  = string
    scaling_config = object({
      desired_size = number
      min_size     = number
      max_size     = number
    })
  }))

  default = {
    "default" = {
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
      scaling_config = {
        desired_size = 3
        min_size     = 1
        max_size     = 4
      }
    }
  }
}

variable "rds_master_username" {
  description = "Master username for the shared RDS MySQL instance"
  type        = string
  sensitive   = true
}

variable "rds_master_password" {
  description = "Master password for the shared RDS MySQL instance"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.rds_master_password) >= 8 && length(var.rds_master_password) <= 41 && !can(regex("[/@\" ]", var.rds_master_password))
    error_message = "RDS master password must be 8-41 characters and must not contain '/', '@', double quote, or spaces."
  }
}

variable "qa_db_name" {
  description = "QA application database name"
  type        = string
  default     = "qa_app_db"
}

variable "qa_db_username" {
  description = "QA application database username"
  type        = string
  default     = "qa_app_user"
}

variable "qa_db_password" {
  description = "QA application database password"
  type        = string
  sensitive   = true
}

variable "prod_db_name" {
  description = "Production application database name"
  type        = string
  default     = "prod_app_db"
}

variable "prod_db_username" {
  description = "Production application database username"
  type        = string
  default     = "prod_app_user"
}

variable "prod_db_password" {
  description = "Production application database password"
  type        = string
  sensitive   = true
}

variable "grafana_admin_username" {
  description = "Grafana admin username stored in AWS Secrets Manager"
  type        = string
  sensitive   = true
}

variable "grafana_admin_password" {
  description = "Grafana admin password stored in AWS Secrets Manager"
  type        = string
  sensitive   = true
}

variable "enable_mysql_bootstrap" {
  description = "Enable MySQL database/user bootstrap after RDS and SSM tunnel are reachable"
  type        = bool
  default     = false
}
