# Angular .NET Microservices Platform

A reference microservices architecture combining an Angular frontend, .NET 9 backend microservices, an API Gateway (Ocelot), containerization with Docker, orchestration with Kubernetes, and CI/CD via GitHub Actions & Azure Pipelines.

## High-Level Architecture

- Client (Angular) communicates only with API Gateway.
- API Gateway (Ocelot) routes to backend microservices.
- Microservices: UserService & ProductService (clean architecture style: Controllers -> Application/Core -> Infrastructure/Data -> Domain models).
- Shared project for cross-cutting code (DTOs, abstractions, messages, swagger conventions, etc.).
- MSSQL for persistence per service (separate DBs) + optional Redis cache.
- Central API Gateway only endpoint consumed by Angular (ports: Gateway 5000, User 5100, Product 5200).
- Angular enhanced with models, error-handling interceptor, prod environment configuration.
- Container-first design (each component has a Dockerfile; docker-compose for local; Kubernetes manifests in `k8s/`).

## Repository Layout

```
README.md
azure-pipelines.yml
.gitignore
.github/
  workflows/ci-cd.yml
  ISSUE_TEMPLATE/
  dependabot.yml
  pull_request_template.md
src/
  ClientApp/ (Angular SPA)
  ApiGateway/ (Ocelot gateway)
  Microservices/
    UserService/
    ProductService/
  Shared/
k8s/
  namespace.yaml
  angular-client.yaml
  user-service.yaml
  product-service.yaml
  ingress.yaml
scripts/
  deploy.sh
  cleanup.sh
```

## Quick Start (Docker Compose)

```bash
# Build and run (Linux/macOS)
./start-services.sh

# On Windows
start-services.bat
```

Then browse: `http://localhost:4200` (Angular) and `http://localhost:5000` (Gateway). Service Swagger UIs: `http://localhost:5100/swagger` (User), `http://localhost:5200/swagger`, aggregated via gateway (future enhancement).

## Local Development (Without Docker)

1. Start microservices & gateway:
   ```bash
   dotnet restore
   dotnet run --project src/ApiGateway/ApiGateway.csproj
   dotnet run --project src/Microservices/UserService/UserService.csproj
   dotnet run --project src/Microservices/ProductService/ProductService.csproj
   ```
2. Start Angular client:
   ```bash
   cd src/ClientApp
   npm install
   npm start
   ```
3. Navigate to `http://localhost:4200`.

## CI/CD
- GitHub Actions (`.github/workflows/ci-cd.yml`): build, test, lint, docker build & push (conditional), Kubernetes dry-run.
- Azure Pipelines (`azure-pipelines.yml`): optional alternative pipeline for Azure DevOps users.

## Kubernetes Deployment

```bash
# Create namespace & deploy all manifests
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/

# Check resources
kubectl get pods -n angular-micro
```

## Scripts
- `scripts/deploy.sh`: build & apply manifests (image tag param optional).
- `scripts/cleanup.sh`: remove all deployed resources.

## Next Enhancements
- Add central authentication (e.g., IdentityServer / Keycloak / Azure AD B2C).
- Observability stack (OpenTelemetry + Prometheus + Grafana + Loki).
- Message broker (RabbitMQ / Kafka) for async integration.
- Automated integration tests.

## License
MIT (adapt as needed).
