# Angular .NET Microservices Platform — Technical Documentation

A cloud-native reference architecture combining an Angular 20 SPA, .NET 9 microservices, an Ocelot API Gateway, SQL Server persistence, Docker, and Kubernetes — wired up with both GitHub Actions and Azure Pipelines CI/CD.

---

## 1. Overview

| Aspect | Details |
|---|---|
| Frontend | Angular 20.1.6 (Material 20.1.5) served by NGINX in production |
| Backend | ASP.NET Core 9.0 (3 services: ApiGateway, UserService, ProductService) |
| API Gateway | Ocelot 23.0.0 |
| Database | Microsoft SQL Server 2022 Express (one DB per microservice) |
| Cache | Redis 7-alpine (provisioned, not yet integrated) |
| Local Orchestration | Docker Compose v3.9 |
| Cloud Orchestration | Kubernetes (namespace `angular-micro`) with NGINX Ingress |
| CI/CD | GitHub Actions + Azure Pipelines |
| Container Registry | GitHub Container Registry (ghcr.io) |

---

## 2. Repository Layout

```
AngularDotNetMicroservices/
├── MicroservicesApp.sln              # Solution: ApiGateway, UserService, ProductService
├── docker-compose.yml                # Local multi-container stack
├── azure-pipelines.yml               # Azure DevOps pipeline
├── deploy-local.sh                   # End-to-end K8s deploy + DB bootstrap script
├── start-services.sh / .bat          # Docker Compose launcher
├── README.md / DOCUMENTATION.md
├── .github/
│   ├── workflows/ci-cd.yml           # GitHub Actions pipeline
│   └── dependabot.yml                # npm + nuget + docker weekly updates
├── src/
│   ├── ApiGateway/                   # Ocelot gateway (.NET 9)
│   ├── Microservices/
│   │   ├── UserService/              # User CRUD (.NET 9 + EF Core)
│   │   └── ProductService/           # Product CRUD (.NET 9 + EF Core)
│   ├── ClientApp/                    # Angular 20 SPA
│   └── Shared/                       # Reserved for shared libraries (currently empty)
├── k8s/                              # Kubernetes manifests
│   ├── namespace.yaml
│   ├── angular-client.yaml
│   ├── api-gateway.yaml
│   ├── user-service.yaml
│   ├── product-service.yaml
│   ├── sql-server.yaml
│   ├── sqlserver-pv.yaml
│   ├── ingress.yaml
│   ├── nodeport.yaml
│   ├── redis.yaml
│   └── Jobs/                         # DB init / migration jobs
├── scripts/
│   ├── deploy.sh                     # Apply manifests with dynamic image tags (uses yq)
│   └── cleanup.sh                    # Remove all K8s resources
└── tests/                            # Reserved (no test projects yet)
```

---

## 3. Architecture

### 3.1 Logical Flow

```
[Browser] → [Angular SPA :4200/:80]
                │
                ▼
        [Ocelot API Gateway :5000]
              │           │
              ▼           ▼
   [UserService :5100]  [ProductService :5200]
              │           │
              ▼           ▼
       [UserServiceDB] [ProductServiceDB]   (both on SQL Server :1433)
```

The Angular client **only ever calls the API Gateway** — it never reaches the microservices directly. Each microservice owns its own database (database-per-service pattern).

### 3.2 Component Responsibilities

| Component | Responsibility |
|---|---|
| Angular Client | UI, forms, validation, REST consumption, error interception |
| API Gateway (Ocelot) | Routing, CORS, single public surface, health aggregation |
| UserService | User CRUD, EF Core migrations, seeding, health checks |
| ProductService | Product CRUD, EF Core migrations, seeding, health checks |
| SQL Server | Persistence (one DB per service) |

---

## 4. Backend Services

### 4.1 API Gateway — `src/ApiGateway/`

- **Framework:** ASP.NET Core 9.0
- **Port:** `5000`
- **Key packages:** `Ocelot 23.0.0`, `Ocelot.Provider.Consul 23.0.0`, `Microsoft.AspNetCore.OpenApi 9.0.7`
- **Routing config:** `ocelot.json`
- **Health endpoint:** `GET /health` → `{ status: "Healthy", service: "ApiGateway" }`
- **CORS:** `allow-all` (development-grade)

Configured downstream routes:

| Upstream (client → gateway) | Downstream (gateway → service) | Methods |
|---|---|---|
| `/api/users` | `UserService:5100/api/users` | GET, POST, OPTIONS |
| `/api/users/{id}` | `UserService:5100/api/users/{id}` | GET, PUT, DELETE |
| `/api/products` | `ProductService:5200/api/products` | GET, POST, OPTIONS |
| `/api/products/{id}` | `ProductService:5200/api/products/{id}` | GET, PUT, DELETE |
| `/health` | `UserService:5100/health` | GET |

### 4.2 UserService — `src/Microservices/UserService/`

- **Framework:** ASP.NET Core 9.0 — **Port:** `5100`
- **Database:** `UserServiceDB` (SQL Server)
- **Layout:** `Controller/`, `Data/`, `Models/`, `DTO/`, `Migrations/`

Core packages:
- `Microsoft.EntityFrameworkCore` 9.0.0 (+ `.SqlServer`, `.Design`, `.Tools`)
- `Swashbuckle.AspNetCore` 6.5.0
- `Microsoft.Extensions.Diagnostics.HealthChecks` 9.0.0 (+ `.EntityFrameworkCore`)

`User` entity: `Id`, `FirstName`, `LastName`, `Email` (unique index), `CreatedAt`, `UpdatedAt`. Three sample users are seeded on first startup (Alice, Bob, Charlie). Two repository implementations exist: `UserRepository` (EF Core) and `InMemoryUserRepository` (fallback).

Endpoints (`/api/users`): list, get-by-id, create, update, delete. Health: `GET /health` includes EF Core `DbContext` check. Swagger at `/swagger`.

### 4.3 ProductService — `src/Microservices/ProductService/`

- **Framework:** ASP.NET Core 9.0 — **Port:** `5200`
- **Database:** `ProductServiceDB` (SQL Server)
- **Layout:** `Controllers/`, `Data/`, `Models/`, `DTOs/`, `Repositories/`, `Migrations/`

`Product` entity: `Id`, `Name` (indexed, required), `Description`, `Price` (decimal(18,2), > 0), `StockQuantity` (>= 0), `CreatedAt`, `UpdatedAt`. Five products seeded on startup (Keyboard, Mouse, Monitor, Dock, Headset).

Endpoints (`/api/products`): standard CRUD. Health and Swagger as in UserService.

### 4.4 Database Strategy

- **Code-first EF Core migrations** are applied automatically at service startup.
- Each service gets its own DB; no cross-service joins.
- Connection string is supplied via `ConnectionStrings__DefaultConnection` env var (Docker Compose) or via Kubernetes Secret (`user-service-secret`, `product-service-secret`).

> ⚠️ **Note:** SA password differs between environments — `Hitesh12@` in `docker-compose.yml`, `Hitesh12@A` in `k8s/sql-server.yaml`. Both are committed plaintext and should be moved to environment-specific secret stores before any non-local use.

---

## 5. Frontend — Angular Client (`src/ClientApp/`)

- **Angular:** 20.1.6 (standalone components, signals-ready)
- **UI:** Angular Material 20.1.5 + CDK
- **TypeScript:** ~5.8.2
- **Styling:** SCSS

### 5.1 Layout

```
src/ClientApp/src/
├── app/
│   ├── app.ts / app.html / app.routes.ts / app.config.ts
│   ├── components/
│   │   ├── home/
│   │   ├── users/        # Reactive forms, Material table, full CRUD, snackbar feedback
│   │   └── products/     # Forms-based CRUD list
│   ├── services/
│   │   ├── user.service.ts     # Observable CRUD with retry + catchError
│   │   └── product.service.ts
│   ├── models/
│   │   ├── user.model.ts       # User + CreateUserRequest interfaces
│   │   └── product.model.ts
│   ├── core/
│   │   └── http-error.interceptor.ts   # Adds X-Request-Id (uuid) + console error logging
│   └── shared/
├── environments/
│   ├── environment.ts          # apiUrl: http://api-gateway:5000/api
│   └── environment.prod.ts     # same, container DNS-based
├── main.ts / index.html / styles.scss
```

### 5.2 Routing

| Path | Component |
|---|---|
| `/` → `/home` | redirect |
| `/home` | HomeComponent |
| `/users` | UsersComponent |
| `/products` | ProductsComponent |
| `**` | wildcard → `/home` |

### 5.3 Build & Serve

Production build emits to `dist/client-app/browser/` and is served by NGINX (`nginx.conf`) inside a slim Alpine image.

---

## 6. Containerization

### 6.1 docker-compose.yml

Bridge network `microservices-network`; persistent volumes `mssql_data` and `redis_data`.

| Service | Image / Build | Host:Container | Notes |
|---|---|---|---|
| `angular-client` | `src/ClientApp/Dockerfile` (node 22 → nginx) | `4200:80` | API_BASE_URL=`http://api-gateway:5000/api` |
| `api-gateway` | `src/ApiGateway/Dockerfile` | `5000:5000` | Development env |
| `user-service` | `src/Microservices/UserService/Dockerfile` | `5100:5100` | DependsOn `sqlserver`; `/health` curl healthcheck |
| `product-service` | `src/Microservices/ProductService/Dockerfile` | `5200:5200` | DependsOn `sqlserver`; `/health` curl healthcheck |
| `sqlserver` | `mcr.microsoft.com/mssql/server:2022-latest` | `1433:1433` | Express edition; sqlcmd healthcheck |
| `redis` | `redis:7-alpine` | `6379:6379` | Append-only mode; not yet wired into services |

### 6.2 Dockerfiles

All .NET services use a multi-stage build: `mcr.microsoft.com/dotnet/sdk:9.0` for restore/publish → `mcr.microsoft.com/dotnet/aspnet:9.0` for runtime. The Angular Dockerfile uses `node:22-alpine` for build → `nginx:stable-alpine` for runtime with a custom `nginx.conf` for SPA history-mode routing.

---

## 7. Kubernetes Deployment (`k8s/`)

Namespace: **`angular-micro`**

| Manifest | Purpose |
|---|---|
| `namespace.yaml` | Creates the namespace |
| `angular-client.yaml` | Deployment + **LoadBalancer** Service (port 80) |
| `api-gateway.yaml` | Deployment + ClusterIP Service (port 5000) |
| `user-service.yaml` | Deployment with `mssql-tools` initContainer (waits for SQL) + ClusterIP (5100); env from Secret `user-service-secret` |
| `product-service.yaml` | Deployment with `mssql-tools` initContainer + ClusterIP (5200); env from Secret `product-service-secret` |
| `sql-server.yaml` | Deployment + ClusterIP (1433); PVC-backed `/var/opt/mssql`; runs as root |
| `sqlserver-pv.yaml` | `sqlserver-pvc` (1Gi, ReadWriteOnce, hostpath) |
| `ingress.yaml` | NGINX Ingress on host `localhost`: `/api(/|$)(.*)` → gateway, `/(.*)` → angular-client |
| `nodeport.yaml` | NodePort exposing the ingress controller (31583/32716) |
| `redis.yaml` | Optional Redis deployment |
| `Jobs/init-database-job.yaml` | Bootstraps databases |
| `Jobs/init-user-migrations.yaml` | Runs UserService EF migrations |
| `Jobs/init-product-migrations.yaml` | Runs ProductService EF migrations |

Container images all live at `ghcr.io/hitsshaa/microservicesapp/<service>:latest`.

---

## 8. Deployment Workflows

### 8.1 Local — Docker Compose

```bash
./start-services.sh        # Linux/macOS
start-services.bat         # Windows
```

Endpoints:
- Angular: <http://localhost:4200>
- Gateway: <http://localhost:5000>
- UserService Swagger: <http://localhost:5100/swagger>
- ProductService Swagger: <http://localhost:5200/swagger>

### 8.2 Local — Without Docker

```bash
dotnet restore
dotnet run --project src/ApiGateway/ApiGateway.csproj
dotnet run --project src/Microservices/UserService/UserService.csproj
dotnet run --project src/Microservices/ProductService/ProductService.csproj

cd src/ClientApp && npm install && npm start
```

### 8.3 Kubernetes — `deploy-local.sh`

End-to-end script that:
1. Creates / recreates the `angular-micro` namespace
2. Installs the NGINX Ingress controller
3. Creates connection-string Secrets
4. Applies all manifests under `k8s/`
5. Waits for SQL Server readiness, then bootstraps `UserServiceDB` and `ProductServiceDB` using local `sqlcmd`, `kubectl exec`, or a temporary `mssql-tools` pod (whichever is available)
6. Waits for microservice pods to be ready and prints final status

```bash
./deploy-local.sh
```

### 8.4 Kubernetes — Direct apply

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/
kubectl get pods -n angular-micro
```

`scripts/deploy.sh` is a slimmer alternative that uses `yq` to inject dynamic image tags before applying.

---

## 9. CI/CD

### 9.1 GitHub Actions — `.github/workflows/ci-cd.yml`

Triggers: push and PR on `main`/`develop`. Concurrency-limited to one run per branch.

1. **Backend** — .NET 9 restore → build (Release) → test
2. **Frontend** — Node 20, `npm ci`, optional lint, production build
3. **Docker** — needs both above; logs into GHCR and builds + pushes:
   - `ghcr.io/<repo>/api-gateway:latest`
   - `ghcr.io/<repo>/user-service:latest`
   - `ghcr.io/<repo>/product-service:latest`
   - `ghcr.io/<repo>/angular-client:latest`

### 9.2 Azure Pipelines — `azure-pipelines.yml`

Three stages:
1. **Build** — parallel backend (.NET 9) + frontend (Node 20)
2. **Containerize** — builds and pushes images tagged with `$(Build.SourceVersion)`
3. **Deploy** — applies `k8s/*.yaml` via the `KubernetesManifest` task (only on `main`)

### 9.3 Dependabot — `.github/dependabot.yml`

Weekly checks for: `npm` (under `src/ClientApp`), `nuget` (root), and `docker` (root).

---

## 10. Observability & Health

| Service | Endpoint | Detail |
|---|---|---|
| API Gateway | `GET /health` | Returns JSON status |
| UserService | `GET /health` | Includes EF Core DB context check |
| ProductService | `GET /health` | Includes EF Core DB context check |

Frontend `HttpErrorInterceptor` attaches a UUID `X-Request-Id` to every request and logs HTTP errors to the browser console. Distributed tracing, metrics, and log aggregation (OpenTelemetry, Prometheus, Grafana, Loki) are listed on the roadmap but not yet wired up.

---

## 11. Security Notes

- **No authentication/authorization** is currently implemented. All endpoints are anonymous.
- CORS is set to **`allow-all`** on every service — acceptable for local dev, must tighten before any shared deployment.
- DB credentials are committed in plaintext in `docker-compose.yml` and `k8s/sql-server.yaml`. Move to a secrets manager (Kubernetes Secrets sealed with SealedSecrets / SOPS, Azure Key Vault, AWS Secrets Manager, etc.) before promoting beyond local.
- SA passwords differ between Docker Compose (`Hitesh12@`) and Kubernetes (`Hitesh12@A`) — keep this in mind when troubleshooting connection issues.

---

## 12. Tests

The `tests/` directory and `MicroservicesApp.sln` currently contain **no test projects**. Frontend testing scaffolding (Jasmine 5.8, Karma 6.4) is present in `package.json` but no specs are checked in. CI runs `dotnet test` and `npm run lint --if-present` — both currently no-ops.

---

## 13. Ports Reference

| Service | Local (compose) | K8s internal | K8s external |
|---|---|---|---|
| Angular client | 4200 | 80 | LoadBalancer + Ingress `/` |
| API Gateway | 5000 | 5000 | Ingress `/api/*` |
| UserService | 5100 | 5100 | (internal only) |
| ProductService | 5200 | 5200 | (internal only) |
| SQL Server | 1433 | 1433 | (internal only) |
| Redis | 6379 | 6379 | (internal only) |

---

## 14. Roadmap

- Centralized authentication (IdentityServer / Keycloak / Azure AD B2C)
- Asynchronous communication via RabbitMQ or Kafka
- OpenTelemetry tracing + Prometheus metrics + Grafana dashboards + Loki logs
- Real test suites (xUnit/NUnit for .NET, Jasmine + Cypress/Playwright for Angular)
- Wire up Redis cache for read-heavy product queries
- Tighten CORS and replace plaintext DB credentials

---

## 15. Quick File Pointers

| Concern | File |
|---|---|
| Gateway routes | `src/ApiGateway/ocelot.json` |
| Angular API base URL | `src/ClientApp/src/environments/environment.ts` (and `.prod.ts`) |
| User schema / seed | `src/Microservices/UserService/Data/UserDbContext.cs` |
| Product schema / seed | `src/Microservices/ProductService/Data/ProductDbContext.cs` |
| Local stack | `docker-compose.yml` |
| K8s end-to-end deploy | `deploy-local.sh` |
| GitHub CI | `.github/workflows/ci-cd.yml` |
| Azure CI | `azure-pipelines.yml` |
| HTTP error/uuid logic | `src/ClientApp/src/app/core/http-error.interceptor.ts` |
