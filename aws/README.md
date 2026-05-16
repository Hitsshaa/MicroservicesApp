# AWS Deployment

This directory contains everything needed to host the stack on AWS.
The full design is in `docs/superpowers/specs/2026-05-16-aws-deployment-design.md`.

## Layout

| File | Purpose |
|---|---|
| `eksctl-cluster.yaml` | EKS cluster + VPC + managed node group definition |
| `iam/github-oidc-trust-policy.json` | Trust policy for the GitHub Actions deployer role |
| `iam/gh-actions-deployer-policy.json` | Permissions policy for that role |
| `iam/eks-secrets-reader-policy.json` | Permissions policy for the in-cluster IRSA role |
| `cloudfront-distribution.json` | CloudFront distribution config (S3 SPA + ALB API origin) |
| `bootstrap.sh` | One-time setup script: OIDC, IAM, ECR, EKS, add-ons, RDS, Secrets Manager, IRSA, S3 |
| `teardown.sh` | Reverse of bootstrap — run between learning sessions to stop the meter |

## Tools required

`aws cli` v2, `eksctl`, `kubectl`, `helm` v3, `jq`.

## First-time setup

```bash
export AWS_ACCOUNT_ID=123456789012
export AWS_REGION=us-east-1
export GITHUB_REPO=hitsshaa/AngularDotNetMicroservices
export RDS_ADMIN_PASSWORD='ChooseAStrongPasswordHere!'

./aws/bootstrap.sh
```

The script prints a checklist of finishing steps at the end (CloudFront OAC + distribution, S3 bucket policy, EKS auth mapping, placeholder replacement in `k8s/serviceaccount-*.yaml`, GitHub repo variables).

## After bootstrap

Push to `main`. The GitHub Actions workflow (`.github/workflows/ci-cd.yml`) will:

1. Test backend + frontend
2. Assume the deployer role via OIDC (no AWS keys in GitHub secrets)
3. Build + push images to ECR (tagged with `latest` and the commit SHA)
4. `kubectl apply -f k8s/` then `kubectl set image` to roll out
5. `npm run build` the Angular app, `aws s3 sync` to the SPA bucket, invalidate CloudFront

## Verifying

```bash
kubectl get pods -n angular-micro
kubectl logs -n angular-micro deploy/user-service | grep -i migration

CF_DOMAIN=$(aws cloudfront get-distribution --id "$CLOUDFRONT_DISTRIBUTION_ID" --query 'Distribution.DomainName' --output text)
curl "https://${CF_DOMAIN}/api/users"
curl "https://${CF_DOMAIN}/api/products"
open "https://${CF_DOMAIN}/"
```

## Tearing down (very important — the stack costs ~$8/day idle)

```bash
./aws/teardown.sh
```

## Cost estimate (always-on, us-east-1)

| Resource | ~Monthly |
|---|---|
| EKS control plane | $73 |
| 2 × t3.medium nodes | $60 |
| NAT Gateway + data | $35 |
| RDS db.t3.small SQL Server Express | $30 |
| Application Load Balancer | $18 |
| CloudFront + S3 + ECR + Secrets Manager | < $5 |
| **Total** | **~$220** |
