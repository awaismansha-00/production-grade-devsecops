output "qa_db_name" {
  description = "QA database name"
  value       = mysql_database.qa.name
}

output "qa_db_username" {
  description = "QA database username"
  value       = mysql_user.qa.user
}

output "prod_db_name" {
  description = "Production database name"
  value       = mysql_database.prod.name
}

output "prod_db_username" {
  description = "Production database username"
  value       = mysql_user.prod.user
}