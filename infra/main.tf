terraform {
  required_version = ">= 1.9.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.10"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.10"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

provider "google-beta" {
  project = var.gcp_project_id
  region  = var.gcp_region
}

locals {
  cluster_name = "angular-micro"
  namespace    = "angular-micro"

  app_services = ["api-gateway", "user-service", "product-service", "angular-client"]

  # The .NET services that need a DB connection (api-gateway and angular-client don't)
  db_services = ["user-service", "product-service"]

  service_ports = {
    api-gateway     = 5000
    user-service    = 5100
    product-service = 5200
    angular-client  = 80
  }

  required_apis = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "sqladmin.googleapis.com",
    "secretmanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "iamcredentials.googleapis.com",
    "iam.googleapis.com",
    "servicenetworking.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ]
}

# Enable the GCP APIs we need. project_services keeps Terraform in charge.
resource "google_project_service" "apis" {
  for_each = toset(local.required_apis)

  project            = var.gcp_project_id
  service            = each.value
  disable_on_destroy = false
}
