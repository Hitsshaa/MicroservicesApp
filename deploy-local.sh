# #!/bin/bash
# set -e  # stop script if any command fails

# NAMESPACE="angular-micro"

# echo "🚀 Starting clean deployment to Kubernetes..."

# # Step 0: Delete existing namespace (if it exists)
# if kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
#   echo "🧹 Deleting existing namespace: $NAMESPACE"
#   kubectl delete namespace $NAMESPACE --wait=true
# fi

# # Step 1: Deploy ingress controller (only if not already installed)
# echo "👉 Applying Ingress NGINX controller..."
# kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/cloud/deploy.yaml

# # Step 2: Create namespace
# echo "👉 Creating namespace: $NAMESPACE"
# kubectl create namespace $NAMESPACE

# # Step 3: Create secrets for connection strings
# echo "👉 Creating secrets..."
# kubectl create secret generic user-service-secret \
#   --from-literal=connection-string="Server=sqlserver;Database=UserServiceDB;User=sa;Password=Hitesh12@;TrustServerCertificate=true;" \
#   -n $NAMESPACE

# kubectl create secret generic product-service-secret \
#   --from-literal=connection-string="Server=sqlserver;Database=ProductServiceDB;User=sa;Password=Hitesh12@;TrustServerCertificate=true;" \
#   -n $NAMESPACE

# # Step 4: Apply all manifests (deployments, services, PVCs)
# echo "👉 Applying Kubernetes manifests..."
# kubectl apply -f k8s/ -n $NAMESPACE

# # Step 5: Wait for SQL Server pod to be ready
# echo "⏳ Waiting for SQL Server pod to be ready..."
# kubectl wait --for=condition=Ready pod -l app=sqlserver -n $NAMESPACE --timeout=180s

# # Step 6: Wait for UserService pod to be ready
# echo "⏳ Waiting for UserService pod to be ready..."
# kubectl wait --for=condition=Ready pod -l app=user-service -n $NAMESPACE --timeout=180s

# # Step 7: Wait for ProductService pod to be ready
# echo "⏳ Waiting for ProductService pod to be ready..."
# kubectl wait --for=condition=Ready pod -l app=product-service -n $NAMESPACE --timeout=180s

# # Step 8: Show deployment status
# echo "✅ Deployment complete. Pods and services in $NAMESPACE:"
# kubectl get pods -n $NAMESPACE
# kubectl get svc -n $NAMESPACE
#!/bin/bash
set -e  # stop script if any command fails

NAMESPACE="angular-micro"

echo "🚀 Starting clean deployment to Kubernetes..."

# Step 0: Delete existing namespace (if it exists)
if kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
  echo "🧹 Deleting existing namespace: $NAMESPACE"
  kubectl delete namespace $NAMESPACE --wait=true
fi

# Step 1: Deploy ingress controller (only if not already installed)
echo "👉 Applying Ingress NGINX controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.1/deploy/static/provider/cloud/deploy.yaml

# Step 2: Create namespace
echo "👉 Creating namespace: $NAMESPACE"
kubectl create namespace $NAMESPACE

# Step 3: Create secrets for connection strings
echo "👉 Creating secrets..."
kubectl create secret generic user-service-secret \
  --from-literal=connection-string="Server=sqlserver.angular-micro.svc.cluster.local;Database=UserServiceDB;User=sa;Password=Hitesh12@;TrustServerCertificate=true;" \
  -n $NAMESPACE

kubectl create secret generic product-service-secret \
  --from-literal=connection-string="Server=sqlserver.angular-micro.svc.cluster.local
  ;Database=ProductServiceDB;User=sa;Password=Hitesh12@;TrustServerCertificate=true;" \
  -n $NAMESPACE

# Step 4: Apply all manifests (deployments, services, PVCs)
echo "👉 Applying Kubernetes manifests..."
kubectl apply -f k8s/ -n $NAMESPACE

# Step 5: Wait for SQL Server pod to be ready
echo "⏳ Waiting for SQL Server pod to be ready..."
kubectl wait --for=condition=Ready pod -l app=sqlserver -n $NAMESPACE --timeout=180s

# Step 5.1: Create databases using external sqlcmd with port-forwarding
# ...existing code...

# Step 5.1: Create databases using local sqlcmd if available, otherwise run inside cluster
echo "🚀 Preparing to create databases ProductServiceDB and UserServiceDB..."

# ensure kubectl present
if ! command -v kubectl >/dev/null 2>&1; then
  echo "❌ kubectl not found in PATH. Install kubectl and retry."
  exit 1
fi

SQL_USER="sa"
SQL_PASS='Hitesh12@'
SQL_SERVICE_NAME="sqlserver"   # change if your Service has another name
SQL_LOCAL_PORT=11433

# helper to run SQL using local sqlcmd
run_sql_local() {
  sqlcmd -S localhost,$SQL_LOCAL_PORT -U "$SQL_USER" -P "$SQL_PASS" -Q "$1"
}

# trap to ensure port-forward is killed
PORT_FORWARD_PID=""
cleanup() {
  if [ -n "$PORT_FORWARD_PID" ]; then
    kill "$PORT_FORWARD_PID" 2>/dev/null || true
    wait "$PORT_FORWARD_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if command -v sqlcmd >/dev/null 2>&1; then
  echo "🚀 sqlcmd found locally — using port-forward to $SQL_SERVICE_NAME:$SQL_LOCAL_PORT"
  kubectl port-forward -n $NAMESPACE svc/$SQL_SERVICE_NAME $SQL_LOCAL_PORT:1433 >/dev/null 2>&1 &
  PORT_FORWARD_PID=$!

  # small warmup
  sleep 10

  echo "⏳ Waiting for SQL Server to accept connections on localhost:$SQL_LOCAL_PORT..."
  for i in {1..24}; do
    if run_sql_local "SELECT 1" >/dev/null 2>&1; then
      echo "✅ SQL Server is ready (local sqlcmd)."
      break
    fi
    echo "Waiting for SQL Server... ($i/24)"
    sleep 5
  done

  if ! run_sql_local "SELECT 1" >/dev/null 2>&1; then
    echo "❌ Unable to connect to SQL Server via local sqlcmd after multiple attempts. Showing recent SQL Server logs:"
    kubectl logs -n $NAMESPACE -l app=sqlserver --tail=50 || true
    exit 1
  fi

  echo "🗄️ Creating databases via local sqlcmd..."
  run_sql_local "IF DB_ID('ProductServiceDB') IS NULL CREATE DATABASE ProductServiceDB;"
  run_sql_local "IF DB_ID('UserServiceDB') IS NULL CREATE DATABASE UserServiceDB;"

  # cleanup handled by trap
else
  echo "ℹ️ sqlcmd not found locally. Attempting to create databases from inside the cluster."

  # Try to exec into the sqlserver pod if it has sqlcmd
  SQL_POD=$(kubectl get pods -n $NAMESPACE -l app=sqlserver -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [ -n "$SQL_POD" ]; then
    echo "ℹ️ Using kubectl exec into pod $SQL_POD"
    if kubectl exec -n $NAMESPACE "$SQL_POD" -- /opt/mssql-tools/bin/sqlcmd -S localhost -U "$SQL_USER" -P "$SQL_PASS" -Q "SELECT 1" >/dev/null 2>&1; then
      kubectl exec -n $NAMESPACE "$SQL_POD" -- /opt/mssql-tools/bin/sqlcmd -S localhost -U "$SQL_USER" -P "$SQL_PASS" -Q "IF DB_ID('ProductServiceDB') IS NULL CREATE DATABASE ProductServiceDB;"
      kubectl exec -n $NAMESPACE "$SQL_POD" -- /opt/mssql-tools/bin/sqlcmd -S localhost -U "$SQL_USER" -P "$SQL_PASS" -Q "IF DB_ID('UserServiceDB') IS NULL CREATE DATABASE UserServiceDB;"
    else
      echo "ℹ️ sqlcmd not present in pod, falling back to temporary mssql-tools pod"
      kubectl run --rm -n $NAMESPACE sqlclient --image=mcr.microsoft.com/mssql-tools --restart=Never --command -- /opt/mssql-tools/bin/sqlcmd -S $SQL_SERVICE_NAME,1433 -U "$SQL_USER" -P "$SQL_PASS" -Q "IF DB_ID('ProductServiceDB') IS NULL CREATE DATABASE ProductServiceDB;"
      kubectl run --rm -n $NAMESPACE sqlclient --image=mcr.microsoft.com/mssql-tools --restart=Never --command -- /opt/mssql-tools/bin/sqlcmd -S $SQL_SERVICE_NAME,1433 -U "$SQL_USER" -P "$SQL_PASS" -Q "IF DB_ID('UserServiceDB') IS NULL CREATE DATABASE UserServiceDB;"
    fi
  else
    echo "❌ Could not find SQL Server pod (label app=sqlserver). Verify the pod label or adjust SQL_POD selection."
    exit 1
  fi
fi




# Step 6: Wait for UserService pod to be ready
echo "⏳ Waiting for UserService pod to be ready..."
kubectl wait --for=condition=Ready pod -l app=user-service -n $NAMESPACE --timeout=180s

# Step 7: Wait for ProductService pod to be ready
echo "⏳ Waiting for ProductService pod to be ready..."
kubectl wait --for=condition=Ready pod -l app=product-service -n $NAMESPACE --timeout=180s

# Step 8: Show deployment status
echo "✅ Deployment complete. Pods and services in $NAMESPACE:"
kubectl get pods -n $NAMESPACE
kubectl get svc -n $NAMESPACE

