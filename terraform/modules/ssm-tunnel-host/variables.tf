variable "name_prefix" {
  description = "Prefix used for tunnel host resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Private subnet ID for the SSM tunnel host"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the SSM tunnel host"
  type        = string
  default     = "t3.micro"
}