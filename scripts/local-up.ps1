# Spin up a local Kubernetes cluster with the full stack on it.
# Requirements: Docker Desktop running, kind on PATH, kubectl on PATH.
#
# Install kind once:
#   winget install --id Kubernetes.kind -e
#
# Run from repo root:
#   .\scripts\local-up.ps1

$ErrorActionPreference = "Stop"
$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $RepoRoot

$ClusterName = "angular-micro"

Write-Host "==> 1. Create the kind cluster (if missing)"
if (-not (kind get clusters | Select-String "^$ClusterName$")) {
    kind create cluster --config k8s/local/kind-config.yaml
} else {
    Write-Host "    cluster '$ClusterName' already exists, skipping"
}

Write-Host "==> 2. Build container images"
docker build -t angular-micro/api-gateway:local      ./src/ApiGateway
docker build -t angular-micro/user-service:local     ./src/Microservices/UserService
docker build -t angular-micro/product-service:local  ./src/Microservices/ProductService

Write-Host "==> 3. Load images into the kind nodes"
kind load docker-image angular-micro/api-gateway:local       --name $ClusterName
kind load docker-image angular-micro/user-service:local      --name $ClusterName
kind load docker-image angular-micro/product-service:local   --name $ClusterName

Write-Host "==> 4. Apply manifests"
kubectl apply -f k8s/local/

Write-Host "==> 5. Wait for Postgres to be ready"
kubectl rollout status statefulset/postgres -n angular-micro --timeout=120s

Write-Host "==> 6. Wait for app deployments"
kubectl rollout status deployment/user-service     -n angular-micro --timeout=120s
kubectl rollout status deployment/product-service  -n angular-micro --timeout=120s
kubectl rollout status deployment/api-gateway      -n angular-micro --timeout=120s

Write-Host ""
Write-Host "============================================================"
Write-Host "Local stack is up. The API gateway is exposed at:"
Write-Host "  http://localhost:5000/health"
Write-Host "  http://localhost:5000/api/users"
Write-Host "  http://localhost:5000/api/products"
Write-Host ""
Write-Host "Run the Angular client locally against it:"
Write-Host "  cd src/ClientApp; npm start"
Write-Host "  (api-gateway is already on http://localhost:5000)"
Write-Host ""
Write-Host "Tear it all down with:"
Write-Host "  .\scripts\local-down.ps1"
Write-Host "============================================================"
