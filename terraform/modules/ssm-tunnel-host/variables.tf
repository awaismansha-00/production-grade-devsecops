variable "name_prefix" {
  description = "Prefix used for tunnel host resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the SSM tunnel host"
  type        = string
}

variable "associate_public_ip_address" {
  description = "Associate a public IP address with the SSM tunnel host"
  type        = bool
  default     = false
}

variable "instance_type" {
  description = "EC2 instance type for the SSM tunnel host"
  type        = string
  default     = "t3.micro"
}
