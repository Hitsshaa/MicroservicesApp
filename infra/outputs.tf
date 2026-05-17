output "gcp_project_id" {
  description = "GCP project ID"
  value       = var.gcp_project_id
}

output "gcp_region" {
  description = "Region everything was deployed into"
  value       = var.gcp_region
}

output "gke_cluster_name" {
  description = "GKE Autopilot cluster name"
  value       = google_container_cluster.autopilot.name
}

output "gke_cluster_endpoint" {
  description = "GKE cluster endpoint (used by kubectl)"
  value       = google_container_cluster.autopilot.endpoint
  sensitive   = true
}

output "artifact_registry_url" {
  description = "Docker registry URL — used by GitHub Actions to push images"
  value       = "${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.app.repository_id}"
}

output "cloudsql_private_ip" {
  description = "Private IP of the Cloud SQL Postgres instance"
  value       = google_sql_database_instance.postgres.private_ip_address
}

output "github_workload_identity_provider" {
  description = "Provider name for google-github-actions/auth (set as GitHub repo variable WIF_PROVIDER)"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "github_deployer_service_account_email" {
  description = "Service account email GitHub Actions impersonates (set as GitHub repo variable WIF_SERVICE_ACCOUNT)"
  value       = google_service_account.github_deployer.email
}

output "user_service_gsa_email" {
  description = "GCP service account email for user-service pods (annotate the K8s SA with this)"
  value       = google_service_account.user_service.email
}

output "product_service_gsa_email" {
  description = "GCP service account email for product-service pods (annotate the K8s SA with this)"
  value       = google_service_account.product_service.email
}

output "next_steps" {
  description = "What to do after terraform apply"
  value       = <<EOT

================================================================
Terraform apply complete.

Resources:
  GKE cluster:         ${google_container_cluster.autopilot.name}
  Cloud SQL endpoint:  ${google_sql_database_instance.postgres.private_ip_address}
  Artifact Registry:   ${var.gcp_region}-docker.pkg.dev/${var.gcp_project_id}/${google_artifact_registry_repository.app.repository_id}

Manual finishing steps:

1. Wire kubectl to the new cluster:
     gcloud container clusters get-credentials ${google_container_cluster.autopilot.name} --region ${var.gcp_region} --project ${var.gcp_project_id}

2. Apply the K8s manifests (substituting the GSA emails into the service accounts):
     $UserGsa    = "${google_service_account.user_service.email}"
     $ProductGsa = "${google_service_account.product_service.email}"
     (Get-Content ..\k8s\gke\serviceaccount-user.yaml).Replace('PLACEHOLDER_USER_GSA', $UserGsa)       | Set-Content ..\k8s\gke\serviceaccount-user.yaml
     (Get-Content ..\k8s\gke\serviceaccount-product.yaml).Replace('PLACEHOLDER_PRODUCT_GSA', $ProductGsa) | Set-Content ..\k8s\gke\serviceaccount-product.yaml
     kubectl apply -f ..\k8s\gke\

3. Set these GitHub repo variables (Settings -> Secrets and variables -> Actions -> Variables):
     GCP_PROJECT_ID       = ${var.gcp_project_id}
     GCP_REGION           = ${var.gcp_region}
     WIF_PROVIDER         = ${google_iam_workload_identity_pool_provider.github.name}
     WIF_SERVICE_ACCOUNT  = ${google_service_account.github_deployer.email}

4. Push to main to trigger CI/CD (build -> push to Artifact Registry -> kubectl rollout).

5. Get the public IP of the gateway and visit it:
     kubectl get svc -n ${local.namespace} angular-client -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
================================================================
EOT
}
