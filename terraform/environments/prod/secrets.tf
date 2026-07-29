resource "aws_secretsmanager_secret" "qa_mysql" {
  name = "qa/mysql_secret"
}

resource "aws_secretsmanager_secret_version" "qa_mysql" {
  count     = var.enable_mysql_bootstrap ? 1 : 0
  secret_id = aws_secretsmanager_secret.qa_mysql.id

  secret_string = jsonencode({
    DB_HOST      = module.rds_mysql.address
    DB_NAME      = var.qa_db_name
    DB_USER      = var.qa_db_username
    DB_PASSWORD  = var.qa_db_password
    DATABASE_URL = "mysql://${var.qa_db_username}:${var.qa_db_password}@${module.rds_mysql.address}:3306/${var.qa_db_name}"
  })

  depends_on = [module.mysql_bootstrap]
}

resource "aws_secretsmanager_secret" "prod_mysql" {
  name = "prod/mysql_secret"
}

resource "aws_secretsmanager_secret_version" "prod_mysql" {
  count     = var.enable_mysql_bootstrap ? 1 : 0
  secret_id = aws_secretsmanager_secret.prod_mysql.id

  secret_string = jsonencode({
    DB_HOST      = module.rds_mysql.address
    DB_NAME      = var.prod_db_name
    DB_USER      = var.prod_db_username
    DB_PASSWORD  = var.prod_db_password
    DATABASE_URL = "mysql://${var.prod_db_username}:${var.prod_db_password}@${module.rds_mysql.address}:3306/${var.prod_db_name}"
  })

  depends_on = [module.mysql_bootstrap]
}
