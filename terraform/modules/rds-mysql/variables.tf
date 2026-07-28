variable "name_prefix" {
  description = "Prefix used for RDS resource names"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for the RDS security group"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the DB subnet group"
  type        = list(string)
}

variable "allowed_security_group_id" {
  description = "Security group allowed to connect to RDS on port 3306"
  type        = list(string)
}

variable "master_username" {
  description = "RDS master username"
  type        = string
  sensitive   = true
}

variable "master_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}

variable "engine_version" {
  description = "MySQL engine version"
  type        = string
  default     = "8.0"
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Initial allocated storage in GiB"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Maximum autoscaled storage in GiB"
  type        = number
  default     = 100
}

variable "backup_retention_period" {
  description = "Automated backup retention in days"
  type        = number
  default     = 7
}

variable "multi_az" {
  description = "Enable Multi-AZ RDS deployment"
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Enable RDS deletion protection"
  type        = bool
  default     = false
}