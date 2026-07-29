variable "vpc_cidr" {
  type        = string
  description = "CIDR block for VPC"
}

variable "availability_zones" {
  type        = list(string)
  description = "List of availability zones for the VPC"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks for public subnets"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks for private subnets"
}

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster"
}

variable "enable_nat_gateway" {
  type        = bool
  description = "Create NAT gateways and private subnet default routes"
  default     = false
}
