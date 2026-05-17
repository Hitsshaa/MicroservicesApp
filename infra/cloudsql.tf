# Cloud SQL — managed PostgreSQL.
# Private IP only — accessible from GKE pods via the VPC peering set up
# in network.tf. Cheaper than public IP (no Cloud SQL Auth Proxy needed)
# but tightly scoped.
resource "google_sql_database_instance" "postgres" {
  name             = "${local.cluster_name}-postgres"
  database_version = "POSTGRES_16"
  region           = var.gcp_region

  deletion_protection = false

  settings {
    edition           = "ENTERPRISE"
    tier              = var.cloudsql_tier
    availability_type = "ZONAL"
    disk_size         = var.cloudsql_storage_gb
    disk_type         = "PD_HDD"
    disk_autoresize   = false

    backup_configuration {
      enabled = false
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc.id
    }
  }

  depends_on = [
    google_project_service.apis,
    google_service_networking_connection.private_vpc,
  ]
}

resource "google_sql_user" "admin" {
  name     = var.cloudsql_admin_username
  instance = google_sql_database_instance.postgres.name
  password = var.cloudsql_admin_password
}

resource "google_sql_database" "user_service" {
  name     = "userservicedb"
  instance = google_sql_database_instance.postgres.name
}

resource "google_sql_database" "product_service" {
  name     = "productservicedb"
  instance = google_sql_database_instance.postgres.name
}
