variable "qa_db_name" {
  description = "QA application database name"
  type        = string
}

variable "qa_db_username" {
  description = "QA application database username"
  type        = string
}

variable "qa_db_password" {
  description = "QA application database password"
  type        = string
  sensitive   = true
}

variable "prod_db_name" {
  description = "Production application database name"
  type        = string
}

variable "prod_db_username" {
  description = "Production application database username"
  type        = string
}

variable "prod_db_password" {
  description = "Production application database password"
  type        = string
  sensitive   = true
}