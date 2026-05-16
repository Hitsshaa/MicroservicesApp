# Each service's connection string is stored as a separate Secrets Manager
# entry, and ECS task definitions reference them via the task-definition
# `secrets` block (much simpler than the EKS Secrets Store CSI Driver was).

locals {
  user_db_connection_string    = "Host=${aws_db_instance.postgres.address};Port=5432;Database=userservicedb;Username=${var.rds_admin_username};Password=${var.rds_admin_password}"
  product_db_connection_string = "Host=${aws_db_instance.postgres.address};Port=5432;Database=productservicedb;Username=${var.rds_admin_username};Password=${var.rds_admin_password}"
}

resource "aws_secretsmanager_secret" "user_db" {
  name                    = "angular-micro/user-service/db"
  description             = "Connection string for the UserService database"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "user_db" {
  secret_id     = aws_secretsmanager_secret.user_db.id
  secret_string = local.user_db_connection_string
}

resource "aws_secretsmanager_secret" "product_db" {
  name                    = "angular-micro/product-service/db"
  description             = "Connection string for the ProductService database"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "product_db" {
  secret_id     = aws_secretsmanager_secret.product_db.id
  secret_string = local.product_db_connection_string
}
