#!/usr/bin/env bash
# One-time AWS bootstrap for the Angular .NET Microservices stack.
# Idempotent where feasible. Run from repo root: ./aws/bootstrap.sh
#
# Required env vars:
#   AWS_ACCOUNT_ID         - 12-digit account id
#   AWS_REGION             - defaults to us-east-1
#   GITHUB_REPO            - e.g. hitsshaa/AngularDotNetMicroservices
#   RDS_ADMIN_PASSWORD     - master password for the RDS instance (>=8 chars)
#
# Tools required: aws cli, eksctl, kubectl, helm, jq

set -euo pipefail

AWS_REGION="${AWS_REGION:-us-east-1}"
: "${AWS_ACCOUNT_ID:?must set AWS_ACCOUNT_ID}"
: "${GITHUB_REPO:?must set GITHUB_REPO (e.g. hitsshaa/AngularDotNetMicroservices)}"
: "${RDS_ADMIN_PASSWORD:?must set RDS_ADMIN_PASSWORD}"

CLUSTER_NAME="angular-micro-eks"
NAMESPACE="angular-micro"
SPA_BUCKET="angular-micro-spa-${AWS_ACCOUNT_ID}"
RDS_ID="angular-micro-sqlserver"

echo "==> 1. Render templated files with account id"
for f in \
  aws/iam/github-oidc-trust-policy.json \
  aws/iam/gh-actions-deployer-policy.json \
  aws/iam/eks-secrets-reader-policy.json; do
  sed -e "s|PLACEHOLDER_AWS_ACCOUNT_ID|${AWS_ACCOUNT_ID}|g" "$f" > "${f}.rendered"
done

echo "==> 2. Create GitHub OIDC provider (idempotent)"
if ! aws iam get-open-id-connect-provider \
    --open-id-connect-provider-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com" \
    >/dev/null 2>&1; then
  aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
fi

echo "==> 3. Create gh-actions-deployer role"
ROLE_NAME="gh-actions-deployer"
TRUST_POLICY=$(sed "s|hitsshaa/AngularDotNetMicroservices|${GITHUB_REPO}|g" aws/iam/github-oidc-trust-policy.json.rendered)
if ! aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
  aws iam create-role \
    --role-name "${ROLE_NAME}" \
    --assume-role-policy-document "${TRUST_POLICY}"
else
  aws iam update-assume-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-document "${TRUST_POLICY}"
fi
aws iam put-role-policy \
  --role-name "${ROLE_NAME}" \
  --policy-name "${ROLE_NAME}-inline" \
  --policy-document file://aws/iam/gh-actions-deployer-policy.json.rendered

DEPLOYER_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${ROLE_NAME}"
echo "    deployer role ARN: ${DEPLOYER_ROLE_ARN}"

echo "==> 4. Create ECR repos"
for repo in api-gateway user-service product-service; do
  aws ecr describe-repositories --repository-names "angular-microservices/${repo}" --region "${AWS_REGION}" \
    >/dev/null 2>&1 || \
    aws ecr create-repository \
      --repository-name "angular-microservices/${repo}" \
      --region "${AWS_REGION}" \
      --image-scanning-configuration scanOnPush=true
  aws ecr put-lifecycle-policy \
    --repository-name "angular-microservices/${repo}" \
    --region "${AWS_REGION}" \
    --lifecycle-policy-text '{"rules":[{"rulePriority":1,"description":"keep last 10","selection":{"tagStatus":"any","countType":"imageCountMoreThan","countNumber":10},"action":{"type":"expire"}}]}'
done

echo "==> 5. Create EKS cluster (this takes ~15 min)"
if ! eksctl get cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" >/dev/null 2>&1; then
  eksctl create cluster -f aws/eksctl-cluster.yaml
fi

echo "==> 6. Install AWS Load Balancer Controller"
eksctl utils associate-iam-oidc-provider --cluster "${CLUSTER_NAME}" --region "${AWS_REGION}" --approve
if ! aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy" >/dev/null 2>&1; then
  curl -sS https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.2/docs/install/iam_policy.json -o /tmp/alb-iam-policy.json
  aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file:///tmp/alb-iam-policy.json
fi
eksctl create iamserviceaccount \
  --cluster="${CLUSTER_NAME}" \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy" \
  --override-existing-serviceaccounts \
  --approve
helm repo add eks https://aws.github.io/eks-charts >/dev/null
helm repo update >/dev/null
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="${CLUSTER_NAME}" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

echo "==> 7. Install Secrets Store CSI Driver + AWS provider"
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts >/dev/null
helm repo update >/dev/null
helm upgrade --install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  -n kube-system \
  --set syncSecret.enabled=true \
  --set enableSecretRotation=true
kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml

echo "==> 8. Create RDS SQL Server instance"
VPC_ID=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" --query 'cluster.resourcesVpcConfig.vpcId' --output text)
PRIVATE_SUBNETS=$(aws ec2 describe-subnets --region "${AWS_REGION}" \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:aws:cloudformation:logical-id,Values=SubnetPrivate*" \
  --query 'Subnets[].SubnetId' --output text)
NODE_SG=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)

aws rds create-db-subnet-group \
  --db-subnet-group-name angular-micro-db-subnets \
  --db-subnet-group-description "Private subnets for angular-micro RDS" \
  --subnet-ids ${PRIVATE_SUBNETS} \
  --region "${AWS_REGION}" 2>/dev/null || true

RDS_SG=$(aws ec2 create-security-group \
  --group-name angular-micro-rds-sg \
  --description "RDS access from EKS nodes" \
  --vpc-id "${VPC_ID}" \
  --region "${AWS_REGION}" \
  --query 'GroupId' --output text 2>/dev/null || \
  aws ec2 describe-security-groups --filters "Name=group-name,Values=angular-micro-rds-sg" "Name=vpc-id,Values=${VPC_ID}" --query 'SecurityGroups[0].GroupId' --output text)
aws ec2 authorize-security-group-ingress \
  --group-id "${RDS_SG}" \
  --protocol tcp --port 1433 \
  --source-group "${NODE_SG}" \
  --region "${AWS_REGION}" 2>/dev/null || true

if ! aws rds describe-db-instances --db-instance-identifier "${RDS_ID}" --region "${AWS_REGION}" >/dev/null 2>&1; then
  aws rds create-db-instance \
    --db-instance-identifier "${RDS_ID}" \
    --db-instance-class db.t3.small \
    --engine sqlserver-ex \
    --engine-version 16.00.4085.2.v1 \
    --master-username sqladmin \
    --master-user-password "${RDS_ADMIN_PASSWORD}" \
    --allocated-storage 20 \
    --storage-type gp3 \
    --storage-encrypted \
    --vpc-security-group-ids "${RDS_SG}" \
    --db-subnet-group-name angular-micro-db-subnets \
    --no-publicly-accessible \
    --backup-retention-period 0 \
    --no-multi-az \
    --license-model license-included \
    --region "${AWS_REGION}"
fi

echo "    waiting for RDS to become available (10-15 min)..."
aws rds wait db-instance-available --db-instance-identifier "${RDS_ID}" --region "${AWS_REGION}"
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier "${RDS_ID}" --region "${AWS_REGION}" \
  --query 'DBInstances[0].Endpoint.Address' --output text)
echo "    RDS endpoint: ${RDS_ENDPOINT}"

echo "==> 9. Create the two application databases on RDS"
kubectl create ns angular-micro 2>/dev/null || true
kubectl run sqlcmd-init --rm -i --restart=Never --image=mcr.microsoft.com/mssql-tools \
  -n angular-micro -- /opt/mssql-tools/bin/sqlcmd \
  -S "${RDS_ENDPOINT}" -U sqladmin -P "${RDS_ADMIN_PASSWORD}" \
  -Q "IF DB_ID('UserServiceDB') IS NULL CREATE DATABASE UserServiceDB; IF DB_ID('ProductServiceDB') IS NULL CREATE DATABASE ProductServiceDB;"

echo "==> 10. Store connection strings in Secrets Manager"
USER_CONN="Server=${RDS_ENDPOINT},1433;Database=UserServiceDB;User Id=sqladmin;Password=${RDS_ADMIN_PASSWORD};TrustServerCertificate=True;"
PROD_CONN="Server=${RDS_ENDPOINT},1433;Database=ProductServiceDB;User Id=sqladmin;Password=${RDS_ADMIN_PASSWORD};TrustServerCertificate=True;"

for entry in "user-service:${USER_CONN}" "product-service:${PROD_CONN}"; do
  svc="${entry%%:*}"
  conn="${entry#*:}"
  secret_id="angular-micro/${svc}/db"
  payload=$(jq -nc --arg cs "${conn}" '{connectionString: $cs}')
  if aws secretsmanager describe-secret --secret-id "${secret_id}" --region "${AWS_REGION}" >/dev/null 2>&1; then
    aws secretsmanager put-secret-value --secret-id "${secret_id}" --secret-string "${payload}" --region "${AWS_REGION}" >/dev/null
  else
    aws secretsmanager create-secret --name "${secret_id}" --secret-string "${payload}" --region "${AWS_REGION}" >/dev/null
  fi
done

echo "==> 11. IRSA service accounts for app pods"
aws iam create-policy --policy-name eks-secrets-reader \
  --policy-document file://aws/iam/eks-secrets-reader-policy.json.rendered \
  --region "${AWS_REGION}" 2>/dev/null || true

for sa in user-service-sa product-service-sa; do
  eksctl create iamserviceaccount \
    --cluster="${CLUSTER_NAME}" \
    --namespace="${NAMESPACE}" \
    --name="${sa}" \
    --attach-policy-arn="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/eks-secrets-reader" \
    --override-existing-serviceaccounts \
    --approve
done

SECRETS_READER_ROLE_ARN=$(aws iam get-role --role-name "eksctl-${CLUSTER_NAME}-addon-iamserviceaccount-${NAMESPACE}-user-service-sa" --query 'Role.Arn' --output text 2>/dev/null || echo "")
echo "    IRSA role ARN (user-service-sa): ${SECRETS_READER_ROLE_ARN}"

echo "==> 12. Create S3 SPA bucket"
aws s3api create-bucket --bucket "${SPA_BUCKET}" --region "${AWS_REGION}" 2>/dev/null || true
aws s3api put-public-access-block \
  --bucket "${SPA_BUCKET}" \
  --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

echo
echo "============================================================"
echo "Bootstrap complete. Next manual steps:"
echo
echo "1. Create the CloudFront Origin Access Control (OAC), then the"
echo "   distribution from aws/cloudfront-distribution.json (replace"
echo "   PLACEHOLDER_OAC_ID, PLACEHOLDER_ALB_DNS_NAME,"
echo "   PLACEHOLDER_TIMESTAMP first)."
echo "2. Apply the S3 bucket policy that grants only the CloudFront"
echo "   distribution principal s3:GetObject on this bucket."
echo "3. Map the gh-actions-deployer role into the EKS cluster:"
echo "     eksctl create iamidentitymapping \\"
echo "       --cluster ${CLUSTER_NAME} --region ${AWS_REGION} \\"
echo "       --arn ${DEPLOYER_ROLE_ARN} \\"
echo "       --group system:masters --username gh-deployer"
echo "4. In each k8s/serviceaccount-*.yaml replace"
echo "     PLACEHOLDER_EKS_SECRETS_READER_ROLE_ARN"
echo "   with the actual IRSA role ARN printed above."
echo "5. Set GitHub repo variables:"
echo "     AWS_ACCOUNT_ID = ${AWS_ACCOUNT_ID}"
echo "     CLOUDFRONT_DISTRIBUTION_ID = <created in step 1>"
echo "6. Push to main to trigger the first deploy."
echo "============================================================"
