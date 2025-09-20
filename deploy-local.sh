#!/bin/bash
set -e  # stop script if any command fails

NAMESPACE="angular-micro"

echo "🚀 Starting local deployment to Kubernetes..."

# Step 1: Deploy ingress controller (only if not already installed)
echo "👉 Applying Ingress NGINX controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/cloud/deploy.yaml

# Step 2: Create namespace if it doesn’t exist
echo "👉 Creating namespace: $NAMESPACE"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Step 3: Create secrets for connection strings
echo "👉 Creating secrets..."
kubectl create secret generic user-service-secret \
  --from-literal=connection-string="Server=sqlserver;Database=UserServiceDB;User=sa;Password=Hitesh12@;TrustServerCertificate=true;" \
  -n $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic product-service-secret \
  --from-literal=connection-string="Server=sqlserver;Database=ProductServiceDB;User=sa;Password=Hitesh12@;TrustServerCertificate=true;" \
  -n $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Step 4: Apply all manifests (deployments, services, PVCs)
echo "👉 Applying Kubernetes manifests..."
kubectl apply -f k8s/ -n $NAMESPACE

# Step 5: Wait for SQL Server pod to be ready
echo "⏳ Waiting for SQL Server pod to be ready..."
kubectl wait --for=condition=Ready pod -l app=sqlserver -n $NAMESPACE --timeout=180s

# Step 6: Wait for UserService pod to be ready (Init Container ensures SQL Server ready)
echo "⏳ Waiting for UserService pod to be ready..."
kubectl wait --for=condition=Ready pod -l app=user-service -n $NAMESPACE --timeout=120s

# Step 7: Wait for ProductService pod to be ready (Init Container ensures SQL Server ready)
echo "⏳ Waiting for ProductService pod to be ready..."
kubectl wait --for=condition=Ready pod -l app=product-service -n $NAMESPACE --timeout=120s

# Step 8: Show deployment status
echo "✅ Deployment complete. Pods and services in $NAMESPACE:"
kubectl get pods -n $NAMESPACE
kubectl get svc -n $NAMESPACE
