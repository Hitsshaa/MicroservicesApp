variable "gcp_project_id" {
  description = "GCP project ID (e.g. angular-micro-12345)"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for regional resources (us-central1 has free-tier perks)"
  type        = string
  default     = "us-central1"
}

variable "github_repository" {
  description = "GitHub repository allowed to deploy via Workload Identity Federation (owner/repo)"
  type        = string
  default     = "Hitsshaa/MicroservicesApp"
}

variable "github_branch" {
  description = "Git branch allowed to deploy via OIDC"
  type        = string
  default     = "main"
}

variable "cloudsql_admin_username" {
  description = "Cloud SQL master username"
  type        = string
  default     = "postgres"
}

variable "cloudsql_admin_password" {
  description = "Cloud SQL master password"
  type        = string
  sensitive   = true
}

variable "cloudsql_tier" {
  description = "Cloud SQL tier (db-f1-micro is the cheapest)"
  type        = string
  default     = "db-f1-micro"
}

variable "cloudsql_storage_gb" {
  description = "Cloud SQL disk size in GB"
  type        = number
  default     = 10
}
