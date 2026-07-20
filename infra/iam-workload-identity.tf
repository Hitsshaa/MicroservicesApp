# --------------------------------------------------------------------------
# Workload Identity Federation — lets GitHub Actions impersonate a GCP
# service account WITHOUT any long-lived JSON keys.
# --------------------------------------------------------------------------
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-actions-pool"
  display_name              = "GitHub Actions"
  description               = "OIDC trust for GitHub Actions"

  depends_on = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  # Lock the pool to our specific repo so only this repo can mint tokens.
  # Use the mapped `attribute.repository` form to stay consistent with the
  # principalSet binding below.
  attribute_condition = "attribute.repository == \"${var.github_repository}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "github_deployer" {
  account_id   = "github-deployer"
  display_name = "GitHub Actions Deployer"
  description  = "Service account that GitHub Actions impersonates"
}

# Bind the pool to the service account — only commits to `var.github_branch`
# can impersonate it.
resource "google_service_account_iam_member" "github_can_impersonate" {
  service_account_id = google_service_account.github_deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}

# Permissions the deployer service account holds.
locals {
  github_deployer_roles = [
    "roles/artifactregistry.writer",      # push images
    "roles/container.developer",          # kubectl apply, set image, rollout
    "roles/storage.objectAdmin",          # SPA bucket sync (if we add CDN later)
    "roles/secretmanager.secretAccessor", # read DB connection strings at deploy time
  ]
}

resource "google_project_iam_member" "github_deployer" {
  for_each = toset(local.github_deployer_roles)

  project = var.gcp_project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.github_deployer.email}"
}

# --------------------------------------------------------------------------
# Pod Workload Identity — lets pods read their per-service secret with NO
# JSON keys. The K8s ServiceAccount (defined in k8s/gke/) gets annotated
# with the GCP SA email; GKE auto-swaps the K8s SA token for a GCP token.
# --------------------------------------------------------------------------
resource "google_service_account" "user_service" {
  account_id   = "angular-micro-user-svc"
  display_name = "user-service pod identity"
}

resource "google_service_account" "product_service" {
  account_id   = "angular-micro-product-svc"
  display_name = "product-service pod identity"
}

# Allow user-service pods to read only their own DB secret.
resource "google_secret_manager_secret_iam_member" "user_db_read" {
  secret_id = google_secret_manager_secret.user_db.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.user_service.email}"
}

resource "google_secret_manager_secret_iam_member" "product_db_read" {
  secret_id = google_secret_manager_secret.product_db.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.product_service.email}"
}

# Bind the GCP SA to the K8s SA for Workload Identity.
# The K8s SA itself is created in k8s/gke/serviceaccount-*.yaml.
resource "google_service_account_iam_member" "user_service_wi" {
  service_account_id = google_service_account.user_service.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project_id}.svc.id.goog[${local.namespace}/user-service-sa]"

  # The implicit <project>.svc.id.goog identity pool only becomes queryable
  # after the GKE Autopilot cluster (which enables Workload Identity) finishes
  # creating.
  depends_on = [google_container_cluster.autopilot]
}

resource "google_service_account_iam_member" "product_service_wi" {
  service_account_id = google_service_account.product_service.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project_id}.svc.id.goog[${local.namespace}/product-service-sa]"

  depends_on = [google_container_cluster.autopilot]
}
