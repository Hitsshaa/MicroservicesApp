#!/usr/bin/env bash
# Reverse the bootstrap so you stop paying for the stack between learning sessions.
# Run from repo root: ./aws/teardown.sh

set -uo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
: "${AWS_ACCOUNT_ID:?must set AWS_ACCOUNT_ID}"

CLUSTER_NAME="angular-micro-eks"
SPA_BUCKET="angular-micro-spa-${AWS_ACCOUNT_ID}"
RDS_ID="angular-micro-sqlserver"

echo "==> Disable + delete CloudFront distribution (manual: provide ID)"
echo "    (skipped here — disable in console or via aws cloudfront update-distribution + delete-distribution)"

echo "==> Empty + delete S3 SPA bucket"
aws s3 rm "s3://${SPA_BUCKET}" --recursive 2>/dev/null || true
aws s3api delete-bucket --bucket "${SPA_BUCKET}" --region "${AWS_REGION}" 2>/dev/null || true

echo "==> Delete Secrets Manager secrets"
for secret_id in angular-micro/user-service/db angular-micro/product-service/db; do
  aws secretsmanager delete-secret --secret-id "${secret_id}" --force-delete-without-recovery --region "${AWS_REGION}" 2>/dev/null || true
done

echo "==> Delete RDS instance"
aws rds delete-db-instance --db-instance-identifier "${RDS_ID}" --skip-final-snapshot --region "${AWS_REGION}" 2>/dev/null || true
echo "    waiting for RDS deletion..."
aws rds wait db-instance-deleted --db-instance-identifier "${RDS_ID}" --region "${AWS_REGION}" 2>/dev/null || true
aws rds delete-db-subnet-group --db-subnet-group-name angular-micro-db-subnets --region "${AWS_REGION}" 2>/dev/null || true

echo "==> Delete EKS cluster (also removes VPC, NAT, node group)"
eksctl delete cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" --wait || true

echo "==> Delete ECR repositories"
for repo in api-gateway user-service product-service; do
  aws ecr delete-repository --repository-name "angular-microservices/${repo}" --force --region "${AWS_REGION}" 2>/dev/null || true
done

echo "==> Delete gh-actions-deployer role"
aws iam delete-role-policy --role-name gh-actions-deployer --policy-name gh-actions-deployer-inline 2>/dev/null || true
aws iam delete-role --role-name gh-actions-deployer 2>/dev/null || true

echo "==> Delete eks-secrets-reader policy"
aws iam delete-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/eks-secrets-reader" 2>/dev/null || true

echo "==> (optional) Delete AWSLoadBalancerControllerIAMPolicy"
echo "    aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy"

echo "==> Teardown complete."
