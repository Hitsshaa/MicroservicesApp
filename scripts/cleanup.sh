#!/usr/bin/env bash
set -euo pipefail
NAMESPACE=angular-micro

echo "Deleting resources in namespace $NAMESPACE"
kubectl delete all --all -n $NAMESPACE || true
kubectl delete ingress --all -n $NAMESPACE || true
