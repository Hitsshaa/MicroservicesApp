# GKE Autopilot Manifests

These manifests run the stack on Google Kubernetes Engine Autopilot. They
are applied by the `backend-deploy` job in `.github/workflows/ci-cd.yml`
after Terraform provisions the cluster.

## Files

| File | Purpose |
|---|---|
| `namespace.yaml` | The `angular-micro` namespace |
| `serviceaccount-user.yaml` | K8s SA bound to the user-service GCP SA via Workload Identity |
| `serviceaccount-product.yaml` | Same for product-service |
| `connection-strings.yaml` | K8s Secrets holding the DB connection strings (rendered at deploy time from Terraform outputs) |
| `api-gateway.yaml` | Ocelot gateway Deployment + ClusterIP Service |
| `user-service.yaml` | UserService Deployment (uses user-service-sa) + ClusterIP |
| `product-service.yaml` | ProductService Deployment (uses product-service-sa) + ClusterIP |
| `angular-client.yaml` | nginx Deployment serving the built SPA + **LoadBalancer Service** (single public IP for the stack) |

## Placeholders rendered at deploy time

| Placeholder | Replaced by |
|---|---|
| `PLACEHOLDER_REGISTRY` | `${gcp_region}-docker.pkg.dev/${project}/angular-micro` |
| `PLACEHOLDER_USER_GSA` | The user-service GCP service account email (from `terraform output`) |
| `PLACEHOLDER_PRODUCT_GSA` | The product-service GCP service account email |
| `PLACEHOLDER_USER_CONN` | The userservicedb connection string |
| `PLACEHOLDER_PRODUCT_CONN` | The productservicedb connection string |

## Architecture

```
[Public Internet]
       |
       v
[GKE LoadBalancer Service (angular-client)]
       |
       v
[angular-client nginx pod] -- serves /, proxies /api/* in-cluster -->
       |                                                                |
       v (in-cluster DNS)                                               |
[api-gateway:5000] <----------------------------------------------------+
       |
       +--> [user-service:5100]    --+
       +--> [product-service:5200]  --+
                                      v
                          [Cloud SQL Postgres (private IP)]
```

A single public LoadBalancer IP exposes everything because nginx (in the
angular-client image) proxies the API path under the same origin.
