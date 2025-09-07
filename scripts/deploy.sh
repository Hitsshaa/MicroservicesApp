#!/usr/bin/env bash
set -euo pipefail
NAMESPACE=angular-micro
IMAGE_TAG="${1:-latest}"

kubectl apply -f k8s/namespace.yaml

# Update image tags on the fly if provided
for svc in angular-client api-gateway user-service product-service; do
  yq eval '.spec.template.spec.containers[0].image |= sub(":.*$"; ":'"$IMAGE_TAG"'")' k8s/${svc}.yaml | kubectl apply -n $NAMESPACE -f -
  echo "Deployed $svc with tag $IMAGE_TAG"
  sleep 1
 done

kubectl apply -f k8s/ingress.yaml -n $NAMESPACE

echo "All services deployed."
