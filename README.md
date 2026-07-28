# Angular + .NET Microservices on GKE

A reference microservices application: an **Angular 20** single-page frontend, two independent **.NET 9** REST services behind a **YARP API Gateway**, backed by **PostgreSQL** (one database per service). It runs locally with Docker Compose and deploys to **Google Kubernetes Engine (GKE Autopilot)** through a fully automated, keyless GitHub Actions pipeline with infrastructure managed by **Terraform**.

It's intentionally small in features (users + products CRUD) but complete in the patterns that matter for real microservices: service-per-domain, database-per-service, an API gateway, container-first packaging, infrastructure as code, and zero long-lived credentials.

---

## Architecture

```
Browser
  │  GET /api/users            (relative path)
  ▼
┌─────────────────────────┐
│  angular-client (nginx) │   serves the SPA + reverse-proxies /api/* 
└───────────┬─────────────┘
            │  http://api-gateway:5000/api/users
            ▼
┌─────────────────────────┐
│  API Gateway (YARP)     │   single entry point; routes by path
└─────┬─────────────┬─────┘
      │             │
      ▼             ▼
┌───────────┐  ┌──────────────┐
│UserService│  │ProductService│   independent .NET 9 services
└─────┬─────┘  └──────┬───────┘
      ▼               ▼
 userservicedb   productservicedb   separate PostgreSQL databases
```

- The frontend only ever talks to **one origin** — nginx serves the SPA and proxies `/api/*` to the gateway, so there are no CORS concerns and a single public IP serves everything.
- The gateway's routing table (the `ReverseProxy` section of `src/ApiGateway/appsettings.json`) maps `/api/users*` → `user-service:5100` and `/api/products*` → `product-service:5200`.
- Each service owns its **own database** and knows nothing about the other — the core microservices tenet.

## Tech stack

| Layer | Technology |
|-------|-----------|
| Frontend | Angular 20, Angular Material, RxJS, nginx (serving + API proxy) |
| API Gateway | .NET 9, YARP |
| Services | .NET 9 Web API, EF Core 9, Swagger |
| Database | PostgreSQL 16 (Cloud SQL in production) |
| Containers | Docker (multi-stage builds) |
| Orchestration | Kubernetes — GKE Autopilot (prod), kind (local) |
| Infrastructure | Terraform (Google provider) |
| CI/CD | GitHub Actions |
| Cloud auth | Workload Identity Federation (no JSON keys anywhere) |

## Ports

| Component | Port |
|-----------|------|
| API Gateway | 5000 |
| UserService | 5100 |
| ProductService | 5200 |
| Angular dev server | 4200 |

---

## Repository layout

```
src/                          The application (the part that runs)
  ClientApp/                  Angular SPA + nginx Dockerfile + nginx.conf
  ApiGateway/                 YARP gateway (routes in appsettings.json)
  Microservices/
    UserService/              Users domain — controller, EF Core, own DB
    ProductService/           Products domain — controller, EF Core, own DB
  Shared/Common/              (placeholder for shared code)

infra/                        Terraform — provisions all of GCP
                              VPC, GKE, Cloud SQL, Artifact Registry,
                              Secret Manager, IAM / Workload Identity

k8s/
  gke/                        Kubernetes manifests for production (GKE)
  local/                      Kubernetes manifests for a local kind cluster

.github/workflows/ci-cd.yml   Build → test → push images → deploy to GKE

scripts/                      Local up/down helpers + Postgres seed
docker-compose.yml            One-command local run (simplest path)
start-services.{sh,bat}       Local convenience launchers
DOCUMENTATION.md              Long-form architecture documentation
```

---

## Running locally

### Option 1 — Docker Compose (simplest)

```bash
# Linux/macOS
./start-services.sh
# Windows
start-services.bat
```

Then open **http://localhost:4200** for the app. The gateway is at `http://localhost:5000`, and each service exposes Swagger at `http://localhost:5100/swagger` (users) and `http://localhost:5200/swagger` (products).

### Option 2 — Run services directly (.NET + Angular)

```bash
# Backend (each in its own terminal)
dotnet run --project src/ApiGateway/ApiGateway.csproj
dotnet run --project src/Microservices/UserService/UserService.csproj
dotnet run --project src/Microservices/ProductService/ProductService.csproj

# Frontend
cd src/ClientApp
npm install
npm start          # http://localhost:4200
```

> Local builds use `src/ClientApp/src/environments/environment.ts` (`apiUrl: http://api-gateway:5000/api`). Production builds swap in `environment.prod.ts` (`apiUrl: /api`) so the browser calls through the nginx proxy.

---

## Deploying to GCP

Prerequisites: a GCP project with billing enabled, the `gcloud` CLI authenticated, and Terraform ≥ 1.9.

```bash
# 1. Provision all infrastructure (VPC, GKE, Cloud SQL, registry, IAM…)
cd infra
cp terraform.tfvars.example terraform.tfvars   # fill in project id + DB password
terraform init
terraform apply

# 2. Deploy the app — just push to main
git push origin main
```

On push to `main`, GitHub Actions builds and tests everything, pushes four container images to Artifact Registry, and rolls them out to the GKE cluster. Get the public IP with:

```bash
kubectl get svc -n angular-micro angular-client
```

## How CI/CD works

`.github/workflows/ci-cd.yml` runs three jobs on every push to `main`:

1. **backend** — `dotnet restore/build/test` on the solution.
2. **frontend** — `npm ci`, lint, and a production Angular build.
3. **deploy** (main only, after 1 & 2 pass) — authenticates to GCP via **Workload Identity Federation** (no stored keys), builds & pushes the four Docker images, then `kubectl apply`s the manifests, syncs DB connection strings from Secret Manager, and rolls out the new images.

Authentication is entirely keyless: GitHub Actions exchanges its OIDC token for short-lived GCP credentials, and each pod reads its database secret through its own GCP service account — no JSON key files exist anywhere in the pipeline or images.

---

## Project status & notes

- Feature scope is deliberately minimal (users + products CRUD) to keep the architecture legible.
- Production defaults favor low cost over resilience (single-zone Cloud SQL, no HA, public GKE endpoint) — harden these before any real use.
- `src/Shared/Common/` and `tests/` are scaffolded placeholders for planned shared code and a test project.

## License

MIT — adapt as needed.
