# Connection strings stored in Secret Manager — pods access them via
# Workload Identity (configured in iam-workload-identity.tf).

locals {
  user_db_connection_string    = "Host=${google_sql_database_instance.postgres.private_ip_address};Port=5432;Database=userservicedb;Username=${var.cloudsql_admin_username};Password=${var.cloudsql_admin_password}"
  product_db_connection_string = "Host=${google_sql_database_instance.postgres.private_ip_address};Port=5432;Database=productservicedb;Username=${var.cloudsql_admin_username};Password=${var.cloudsql_admin_password}"
}

resource "google_secret_manager_secret" "user_db" {
  secret_id = "angular-micro-user-service-db"

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "user_db" {
  secret      = google_secret_manager_secret.user_db.id
  secret_data = local.user_db_connection_string
}

resource "google_secret_manager_secret" "product_db" {
  secret_id = "angular-micro-product-service-db"

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "product_db" {
  secret      = google_secret_manager_secret.product_db.id
  secret_data = local.product_db_connection_string
}
