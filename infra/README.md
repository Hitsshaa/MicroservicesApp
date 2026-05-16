# Terraform Infrastructure — Free-Tier ECS Fargate

Single-command provisioning of the full AWS stack using free-tier-friendly
services: VPC (no NAT Gateway), ECS Fargate (Spot), RDS PostgreSQL on
db.t3.micro, ECR, Secrets Manager, S3 + CloudFront, IAM (OIDC).

The full design context is in
`docs/superpowers/specs/2026-05-16-aws-deployment-design.md`.

## Files

| File | What it provisions |
|---|---|
| `main.tf` | Providers, locals, region |
| `variables.tf` | Inputs (region, GitHub repo, DB password, Fargate sizing) |
| `outputs.tf` | ARNs, endpoints, IDs, and a printed next-steps block |
| `network.tf` | VPC (2 AZs, **public subnets only — no NAT**) + ALB SG + tasks SG |
| `alb.tf` | Application Load Balancer + target group + listener |
| `ecs.tf` | ECS cluster, capacity providers, Cloud Map service discovery, task defs, three services, IAM roles |
| `ecr.tf` | 3 ECR repos with keep-last-10 lifecycle policies |
| `rds.tf` | PostgreSQL 16 on db.t3.micro (free tier eligible) |
| `secrets.tf` | Two Secrets Manager secrets, one per service |
| `s3-cloudfront.tf` | SPA bucket (private, OAC-only), CloudFront with two origins |
| `iam-github-oidc.tf` | GitHub OIDC provider + `gh-actions-deployer` role + ECS deploy permissions |

## Cost while running

| Resource | Approx |
|---|---|
| ECS Fargate (Spot, .25 vCPU × 3) | ~$5/mo if 24/7 |
| RDS db.t3.micro PostgreSQL | **$0** (free tier, 750 hrs/mo for 12 months) |
| ALB | ~$18/mo |
| S3 + CloudFront + ECR + Secrets Manager | < $1/mo (free tier) |
| **Total** | **~$25/mo if 24/7, ~$0 when `service_desired_count = 0`** |

Set `service_desired_count = 0` in `terraform.tfvars` to scale to zero between
sessions — only the ALB ($18/mo) keeps a meter running.

For a **true zero-cost idle**, run `terraform destroy` after each session.

## Prerequisites

- Terraform >= 1.9 — `winget install --id Hashicorp.Terraform -e`
- AWS CLI v2 with credentials configured (`aws configure`)
- AWS account on the paid plan (Free Plan does not allow ECS / RDS — see the
  "Complete account setup" message in the AWS console if you signed up recently)

## Two-phase apply

CloudFront needs the ALB DNS name to exist before the distribution is created.
So we apply in two phases.

### Phase 1 — everything except CloudFront

```powershell
cd infra
Copy-Item terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set rds_admin_password to a real strong password

terraform init
terraform apply -var skip_cloudfront=true -auto-approve
```

Takes ~10 minutes (RDS is the slowest part).

### Between phases — create application databases

The .NET services create their own tables on startup (via
`db.Database.EnsureCreated()`) but the *databases themselves* need to exist
first. Easiest way: connect once with `psql` from the AWS CloudShell (the
RDS instance has no public IP, so you need something inside the VPC or
publicly_accessible turned on temporarily).

Simplest for learning: temporarily flip the RDS to publicly accessible:

```powershell
$rds = terraform output -raw rds_endpoint
$awsRegion = terraform output -raw aws_region

aws rds modify-db-instance --db-instance-identifier angular-micro-postgres `
  --publicly-accessible --apply-immediately --region $awsRegion

# wait ~1 minute for the change to propagate, then connect
$pw = (Select-String '^rds_admin_password' terraform.tfvars).Line -replace '.*=\s*"(.*)"','$1'
$env:PGPASSWORD = $pw
psql -h $rds -U postgres -d appdb -c "CREATE DATABASE userservicedb; CREATE DATABASE productservicedb;"

# turn public access back off
aws rds modify-db-instance --db-instance-identifier angular-micro-postgres `
  --no-publicly-accessible --apply-immediately --region $awsRegion
```

(Don't have psql installed? Use the AWS Console's RDS Query Editor, or
`docker run --rm -it postgres:16-alpine psql ...`.)

### Phase 2 — CloudFront

```powershell
terraform apply -var skip_cloudfront=false -auto-approve
```

Takes ~10 minutes.

### After phase 2

`terraform output` prints `next_steps`. Set the two GitHub repo variables and
push to `main`.

## Verifying

```powershell
# Service status
aws ecs describe-services --cluster angular-micro --services api-gateway user-service product-service --query 'services[].[serviceName,desiredCount,runningCount]' --output table

# Hit the ALB directly
$alb = terraform output -raw alb_dns_name
curl "http://$alb/health"
curl "http://$alb/api/users"
curl "http://$alb/api/products"

# Or via CloudFront
$cf = terraform output -raw cloudfront_domain_name
curl "https://$cf/api/users"
start "https://$cf/"
```

## Tearing down

```powershell
terraform destroy -auto-approve
```

Takes ~10 minutes.

## Scaling to zero between sessions (cheaper than full teardown)

```powershell
terraform apply -var service_desired_count=0 -auto-approve
# ... later, bring tasks back ...
terraform apply -var service_desired_count=1 -auto-approve
```

While at 0, you pay only ALB ($18/mo) + the (free-tier) RDS instance.
After teardown you pay $0.
