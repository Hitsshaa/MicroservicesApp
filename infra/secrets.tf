locals {
  user_db_connection_string    = "Server=${aws_db_instance.sqlserver.address},1433;Database=UserServiceDB;User Id=${var.rds_admin_username};Password=${var.rds_admin_password};TrustServerCertificate=True;"
  product_db_connection_string = "Server=${aws_db_instance.sqlserver.address},1433;Database=ProductServiceDB;User Id=${var.rds_admin_username};Password=${var.rds_admin_password};TrustServerCertificate=True;"
}

resource "aws_secretsmanager_secret" "user_db" {
  name                    = "angular-micro/user-service/db"
  description             = "Connection string for the UserService database"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "user_db" {
  secret_id = aws_secretsmanager_secret.user_db.id
  secret_string = jsonencode({
    connectionString = local.user_db_connection_string
  })
}

resource "aws_secretsmanager_secret" "product_db" {
  name                    = "angular-micro/product-service/db"
  description             = "Connection string for the ProductService database"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "product_db" {
  secret_id = aws_secretsmanager_secret.product_db.id
  secret_string = jsonencode({
    connectionString = local.product_db_connection_string
  })
}
