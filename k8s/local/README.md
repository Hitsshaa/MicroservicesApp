# Local Kubernetes (kind)

Run the whole stack on a single-node Kubernetes cluster on your laptop, with
no cloud account required.

## Prerequisites

- Docker Desktop running
- `kind` (Kubernetes IN Docker) — install once:
  ```powershell
  winget install --id Kubernetes.kind -e
  ```
- `kubectl` (already installed during the AWS setup)

## Spin it up

```powershell
.\scripts\local-up.ps1
```

Takes ~3 minutes. The script:

1. Creates a `kind` cluster named `angular-micro` (or reuses an existing one)
2. Builds the three .NET container images
3. Loads them into the kind nodes (no registry round-trip)
4. Applies everything in `k8s/local/`
5. Waits for Postgres + the three services to become ready

When it's done the **API gateway is reachable on `http://localhost:5000`** —
the cluster's NodePort is mapped to your host's port 5000 via the
`extraPortMappings` block in `k8s/local/kind-config.yaml`.

Open a browser to:

- http://localhost:5000/health
- http://localhost:5000/api/users (3 seeded users)
- http://localhost:5000/api/products (5 seeded products)

To run the Angular SPA against this cluster:

```powershell
cd src/ClientApp
npm install
npm start    # serves at http://localhost:4200, calls http://localhost:5000/api
```

## Tear it down

```powershell
.\scripts\local-down.ps1
```

Deletes the kind cluster. Pure cleanup — no cloud resources to worry about.

## Files

| File | Purpose |
|---|---|
| `kind-config.yaml` | kind cluster config — maps host port 5000 to NodePort 30500 |
| `namespace.yaml` | The `angular-micro` namespace |
| `postgres.yaml` | StatefulSet for Postgres + ConfigMap that seeds the two databases on first boot + PVC + Service |
| `connection-strings.yaml` | Plain K8s Secrets with the two connection strings (in-cluster only) |
| `api-gateway.yaml` | Deployment + NodePort Service for the Ocelot gateway |
| `user-service.yaml` | Deployment + ClusterIP Service for UserService |
| `product-service.yaml` | Deployment + ClusterIP Service for ProductService |

## Differences vs. the AWS manifests (`k8s/aws/`)

| Concern | Local (kind) | AWS (formerly EKS) |
|---|---|---|
| Database | In-cluster Postgres StatefulSet | RDS Postgres |
| Secrets | Plain K8s Secret | AWS Secrets Manager + CSI driver |
| Ingress | Host-mapped NodePort | ALB Ingress / ECS+ALB |
| Images | `kind load docker-image` (local) | ECR pulls |

The application code is identical between local and AWS — only the way the
infrastructure surrounds it differs.
