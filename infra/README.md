# Terraform Infrastructure — GCP (GKE Autopilot)

Single-command provisioning of the full GCP stack using free-tier-friendly
services: VPC + Cloud NAT, GKE Autopilot (1 zonal cluster — control plane is
**free**), Cloud SQL PostgreSQL on `db-f1-micro`, Artifact Registry,
Secret Manager, Workload Identity Federation for GitHub OIDC.

## Files

| File | What it provisions |
|---|---|
| `main.tf` | Providers, GCP API enablement, locals |
| `variables.tf` | Inputs (project ID, region, GitHub repo, DB password) |
| `outputs.tf` | Cluster name, registry URL, GSA emails, next-steps |
| `network.tf` | VPC, subnet, secondary ranges, Cloud NAT, private services peering for Cloud SQL |
| `gke.tf` | GKE Autopilot cluster |
| `cloudsql.tf` | Postgres 16 on db-f1-micro, two databases, admin user |
| `artifact-registry.tf` | Single Docker repository with keep-last-10 |
| `secrets.tf` | Two Secret Manager entries (one per service) |
| `iam-workload-identity.tf` | WIF for GitHub Actions + per-pod GCP service accounts bound to K8s SAs |

## Cost while running

| Resource | Approx monthly |
|---|---|
| GKE Autopilot control plane (1 zonal cluster) | **$0** (free tier) |
| Autopilot workload pods (4 services × small resources) | ~$15–25/mo |
| Cloud SQL db-f1-micro | ~$8/mo |
| Cloud NAT | ~$1/mo (small egress) |
| Artifact Registry + Secret Manager + Cloud Storage | < $1/mo |
| External Load Balancer (for angular-client Service) | ~$18/mo |
| **Total when running** | **~$45/mo, well within $300 trial** |
| **`terraform destroy`** | **$0** |

The $300 GCP trial credit covers ~6 months of continuous use, or much
longer with disciplined `terraform destroy` between sessions.

## Prerequisites

- A GCP project. Create one in the Console → "New Project". Note its **Project ID** (not the name).
- Billing account linked to that project (the $300 trial counts as a billing account).
- `gcloud` CLI installed and authenticated:
  ```powershell
  winget install --id Google.CloudSDK -e
  gcloud init
  gcloud auth application-default login
  ```
- Terraform >= 1.9 (already installed earlier in this project).

## Apply

```powershell
cd infra
Copy-Item terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set gcp_project_id and a real cloudsql_admin_password

terraform init
terraform apply -auto-approve
```

Takes ~10 minutes. The API enablement step is the slow part (Terraform
waits for the APIs to fully propagate before creating dependent resources).

After it completes, `terraform output` prints the manual finishing steps.

## Verifying

```powershell
gcloud container clusters get-credentials angular-micro --region us-central1 --project (terraform output -raw gcp_project_id)

kubectl get pods -n angular-micro
kubectl logs -n angular-micro deploy/user-service | Select-String "schema ready"

# Public IP of the angular-client LoadBalancer (takes 1-2 min to allocate)
$ip = kubectl get svc -n angular-micro angular-client -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
curl "http://$ip/api/users"
start "http://$ip/"
```

## Tearing down

```powershell
terraform destroy -auto-approve
```

Takes ~5 minutes. Removes the cluster, Cloud SQL, network, IAM, and APIs
stay enabled (cheap — they don't cost anything when not used).

## Scaling to zero between sessions (no full teardown)

GKE Autopilot only bills for running Pods. To stop the meter on workloads:

```powershell
kubectl scale deployment -n angular-micro --all --replicas=0
```

You still pay for Cloud SQL (~$8/mo) and the LoadBalancer (~$18/mo), so for
true $0 idle, `terraform destroy` is the better choice.
