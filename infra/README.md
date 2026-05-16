# Terraform Infrastructure

Single-command provisioning of the full AWS stack: VPC, EKS, RDS SQL Server,
ECR repos, Secrets Manager, S3 + CloudFront, IAM (OIDC + IRSA), and the
required Helm releases (AWS Load Balancer Controller, Secrets Store CSI).

The full design is in `docs/superpowers/specs/2026-05-16-aws-deployment-design.md`.

## Files

| File | What it provisions |
|---|---|
| `main.tf` | Provider versions, AWS/kubernetes/helm providers, locals |
| `variables.tf` | Inputs (region, GitHub repo, DB password, sizes) |
| `outputs.tf` | ARNs, endpoints, IDs, next-steps instructions |
| `network.tf` | VPC module (public + private subnets, single NAT) |
| `eks.tf` | EKS module + managed node group + addons + access entry for the deployer role |
| `ecr.tf` | 3 ECR repositories with keep-last-10 lifecycle policies |
| `rds.tf` | SQL Server Express, security group, subnet group |
| `secrets.tf` | Two Secrets Manager secrets, populated with connection strings |
| `s3-cloudfront.tf` | SPA bucket (private, OAC-only), CloudFront distribution with two origins |
| `iam-github-oidc.tf` | GitHub OIDC provider + `gh-actions-deployer` role + permissions |
| `irsa.tf` | Per-pod IRSA roles (one per application, scoped to one secret each) |
| `helm.tf` | AWS Load Balancer Controller + Secrets Store CSI driver + AWS provider |

## Prerequisites

Already installed from the project bootstrap:

```
aws, kubectl, helm, jq, terraform >= 1.9
```

Install Terraform (Windows):

```powershell
winget install --id Hashicorp.Terraform -e
# verify
terraform version
```

You also need `aws configure` to have credentials with `AdministratorAccess`
(or equivalent — VPC, EKS, RDS, IAM, S3, CloudFront, Secrets Manager).

## Two-phase apply

The CloudFront distribution depends on an ALB DNS name that only exists
*after* the `k8s/ingress-alb.yaml` Ingress is applied and the AWS Load
Balancer Controller provisions the actual ALB. So we apply in two phases.

### Phase 1 — everything except CloudFront

```powershell
cd infra
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars and set rds_admin_password to a strong password
terraform init
terraform apply -var skip_cloudfront=true -auto-approve
```

Takes ~25 minutes (EKS + RDS dominate).

### Between phases — bring up the app

```powershell
# 1. Update kubeconfig
aws eks update-kubeconfig --name angular-micro-eks --region us-east-1

# 2. Create the two application databases on RDS (one-shot kubectl pod)
$RdsEndpoint = terraform output -raw rds_endpoint
$Pwd = (Select-String '^rds_admin_password' terraform.tfvars).Line -replace '.*=\s*"(.*)"','$1'
kubectl create ns angular-micro 2>$null
kubectl run sqlcmd-init --rm -i --restart=Never `
  --image=mcr.microsoft.com/mssql-tools -n angular-micro -- `
  /opt/mssql-tools/bin/sqlcmd -S $RdsEndpoint -U sqladmin -P "$Pwd" `
  -Q "IF DB_ID('UserServiceDB') IS NULL CREATE DATABASE UserServiceDB; IF DB_ID('ProductServiceDB') IS NULL CREATE DATABASE ProductServiceDB;"

# 3. Substitute IRSA ARNs into the service account manifests
$UserIrsa = terraform output -raw user_service_irsa_role_arn
$ProductIrsa = terraform output -raw product_service_irsa_role_arn
(Get-Content ..\k8s\serviceaccount-user.yaml).Replace('PLACEHOLDER_EKS_SECRETS_READER_ROLE_ARN', $UserIrsa) | Set-Content ..\k8s\serviceaccount-user.yaml
(Get-Content ..\k8s\serviceaccount-product.yaml).Replace('PLACEHOLDER_EKS_SECRETS_READER_ROLE_ARN', $ProductIrsa) | Set-Content ..\k8s\serviceaccount-product.yaml

# 4. Apply the k8s manifests (this is what CI normally does, but we do it
#    once here so the Ingress creates the ALB before phase 2)
$Registry = terraform output -raw ecr_registry_url
(Get-ChildItem ..\k8s -Filter *.yaml).FullName | ForEach-Object {
  (Get-Content $_).Replace('PLACEHOLDER_ECR_URI', $Registry) | Set-Content $_
}
kubectl apply -f ..\k8s\

# 5. Wait for the ALB to be provisioned (~2-3 min)
kubectl wait ingress/api-gateway-ingress -n angular-micro --for=jsonpath='{.status.loadBalancer.ingress[0].hostname}' --timeout=300s
```

### Phase 2 — CloudFront

```powershell
terraform apply -var skip_cloudfront=false -auto-approve
```

Takes ~10 minutes (CloudFront takes most of that).

### After phase 2

`terraform output` prints `next_steps` with the remaining manual bits:

- Set GitHub repo variables `AWS_ACCOUNT_ID` and `CLOUDFRONT_DISTRIBUTION_ID`
- Commit the IRSA ARN substitution in `k8s/serviceaccount-*.yaml`
- Push to `main` to trigger CI/CD (which will now redeploy on every commit)
- Browse to the CloudFront domain

## Verifying

```powershell
kubectl get pods -n angular-micro              # all Running
kubectl logs -n angular-micro deploy/user-service | Select-String migration

$Cf = terraform output -raw cloudfront_domain_name
curl https://$Cf/api/users          # 3 seeded users
curl https://$Cf/api/products       # 5 seeded products
start https://$Cf/                  # opens browser
```

## Tearing down (run between learning sessions)

```powershell
terraform destroy -auto-approve
```

Takes ~15 minutes. Removes everything Terraform created (cluster, RDS, VPC,
ECR with `force_destroy`, S3, CloudFront, IAM). If `terraform destroy` fails
on the OIDC provider (because GitHub's thumbprint changed), delete it
manually from the IAM console.

## Cost estimate (always-on, us-east-1)

| Resource | ~Monthly |
|---|---|
| EKS control plane | $73 |
| 2 × t3.medium nodes | $60 |
| NAT Gateway + data | $35 |
| RDS db.t3.small SQL Server Express | $30 |
| Application Load Balancer | $18 |
| CloudFront + S3 + ECR + Secrets Manager | < $5 |
| **Total if always-on** | **~$220** (~$8/day) |

With disciplined `terraform destroy` between sessions, expected actual
spend is single-digit dollars per month.
