resource "google_artifact_registry_repository" "app" {
  location      = var.gcp_region
  repository_id = "angular-micro"
  description   = "Container images for the angular-micro stack"
  format        = "DOCKER"

  cleanup_policies {
    id     = "keep-last-10"
    action = "KEEP"

    most_recent_versions {
      keep_count = 10
    }
  }

  depends_on = [google_project_service.apis]
}
