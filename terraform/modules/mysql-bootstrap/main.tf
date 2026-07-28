resource "mysql_database" "qa" {
  name = var.qa_db_name
}

resource "mysql_database" "prod" {
  name = var.prod_db_name
}

resource "mysql_user" "qa" {
  user               = var.qa_db_username
  host               = "%"
  plaintext_password = var.qa_db_password
}

resource "mysql_user" "prod" {
  user               = var.prod_db_username
  host               = "%"
  plaintext_password = var.prod_db_password
}

resource "mysql_grant" "qa" {
  user       = mysql_user.qa.user
  host       = mysql_user.qa.host
  database   = mysql_database.qa.name
  privileges = ["SELECT", "INSERT", "UPDATE", "DELETE", "CREATE", "ALTER", "INDEX"]
}

resource "mysql_grant" "prod" {
  user       = mysql_user.prod.user
  host       = mysql_user.prod.host
  database   = mysql_database.prod.name
  privileges = ["SELECT", "INSERT", "UPDATE", "DELETE", "CREATE", "ALTER", "INDEX"]
}