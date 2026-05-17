# GKE Autopilot — managed Kubernetes where Google runs the nodes.
# The control plane is FREE for one zonal cluster per billing account.
# You only pay for the Pod resource requests (vCPU + memory + disk).
resource "google_container_cluster" "autopilot" {
  provider = google-beta

  name     = local.cluster_name
  location = var.gcp_region

  enable_autopilot = true
  deletion_protection = false

  network    = google_compute_network.vpc.id
  subnetwork = google_compute_subnetwork.primary.id

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  release_channel {
    channel = "REGULAR"
  }

  # Public endpoint, no master-authorized-networks for learning ease.
  # Production would lock kubectl access down via authorized networks or
  # private endpoint + bastion.

  depends_on = [
    google_project_service.apis,
    google_compute_subnetwork.primary,
  ]
}
