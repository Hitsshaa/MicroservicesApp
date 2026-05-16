# AWS Deployment — Design Spec

**Date:** 2026-05-16
**Status:** Approved (brainstorming complete)
**Project:** AngularDotNetMicroservices
**Goal:** Deploy the existing Angular 20 + .NET 9 microservices stack to AWS for learning purposes, with proper secrets handling.

---

## 1. Goal & Scope

Take the working local stack documented in `DOCUMENTATION.md` and run it on AWS end-to-end:

- Angular SPA served via S3 + CloudFront
- Ocelot API Gateway and the two .NET microservices running on Amazon EKS
- SQL Server on Amazon RDS
- Database credentials in AWS Secrets Manager, mounted into pods via the Secrets Store CSI Driver
- CI/CD via the existing GitHub Actions workflow, authenticated to AWS via OIDC (no long-lived keys)

**In scope:** lift-and-shift of the existing application to AWS, plus replacing the plaintext DB passwords (currently in `docker-compose.yml` and `k8s/sql-server.yaml`) with AWS Secrets Manager.

**Out of scope (deferred from the roadmap):** authentication/authorization, Redis caching, OpenTelemetry/Prometheus/Grafana, async messaging, automated test suites, custom domain + Route 53 + ACM certificates. These remain on the existing roadmap (`DOCUMENTATION.md:362`) and would be follow-on specs.

**Region:** `us-east-1`.

**Audience:** the operator following this spec is the project author, treating this as a learning exercise. The cluster will be spun up for practice sessions and torn down between them to control cost.

---

## 2. Target Architecture

```
[User browser]
      |
      v
[CloudFront distribution]
      |
      +-- (static SPA, default behavior /*) ---> [S3 bucket: angular-micro-spa-<account-id>] (private, OAC-restricted)
      |
      +-- (behavior /api/*) ---> [Application Load Balancer]
                                        |
                                        v
                                  [EKS Service: api-gateway (ClusterIP)]
                                        |
                                        +---> [EKS Service: user-service]    --+
                                        +---> [EKS Service: product-service] --+
                                                                               v
                                                                  [RDS SQL Server :1433]
                                                                      - UserServiceDB
                                                                      - ProductServiceDB

[AWS Secrets Manager]  --(Secrets Store CSI Driver)-->  pods receive DB connection strings as env vars
[Amazon ECR]           --(image pulls)---------------->  EKS nodes
[GitHub Actions]       --(OIDC -> IAM Role)----------->  ECR push, kubectl apply, s3 sync, CloudFront invalidation
```

**Key flow change vs. the local setup:** the Angular SPA is no longer served from an in-cluster NGINX pod. CloudFront serves `/` from S3 and proxies `/api/*` to the ALB fronting the Ocelot gateway. This puts SPA and API behind a single origin, which simplifies CORS and removes the need for a frontend container.

---

## 3. AWS Resources

### 3.1 Networking (VPC)

- New VPC `10.0.0.0/16`, two AZs (`us-east-1a`, `us-east-1b`)
- Two public subnets (host ALB, NAT Gateway)
- Two private subnets (host EKS worker nodes and RDS)
- One Internet Gateway, one NAT Gateway (single NAT for cost — a production deployment would use one per AZ)
- VPC, subnets, route tables, and security groups created implicitly by `eksctl` based on `aws/eksctl-cluster.yaml`

### 3.2 Amazon EKS

- Cluster name: `angular-micro-eks`
- Kubernetes version: 1.30
- One managed node group: 2 × `t3.medium` on-demand
- Add-ons:
  - AWS Load Balancer Controller (installs via Helm; provisions the ALB from the Ingress resource)
  - Secrets Store CSI Driver + AWS provider (installs via Helm; mounts Secrets Manager secrets into pods)
  - EBS CSI driver (managed add-on; only used if any future workload needs PVCs — RDS replaces the SQL Server PVC)
- IRSA (IAM Roles for Service Accounts) enabled; service accounts in the `angular-micro` namespace get scoped AWS permissions without giving the underlying node any privileges.

### 3.3 Amazon ECR

Three private repositories:

- `angular-microservices/api-gateway`
- `angular-microservices/user-service`
- `angular-microservices/product-service`

Each repo has a lifecycle policy keeping the 10 most recent images. The Angular client no longer needs an ECR repo because it ships to S3.

### 3.4 Amazon RDS for SQL Server

- Engine: SQL Server 2022 Express
- Instance class: `db.t3.small` (smallest class that SQL Server Express supports on RDS)
- Storage: 20 GiB gp3, encrypted at rest
- Single-AZ (learning environment)
- Placement: private subnets only
- Security group: ingress on TCP 1433 only from the EKS node security group
- One RDS instance hosting both `UserServiceDB` and `ProductServiceDB` (cheaper than two instances; database isolation maintained at the database level, which matches the current local setup)
- Master credentials: RDS-generated, stored automatically in Secrets Manager

### 3.5 AWS Secrets Manager

Two application secrets:

- `angular-micro/user-service/db` — JSON containing the full ADO.NET connection string for `UserServiceDB`
- `angular-micro/product-service/db` — same for `ProductServiceDB`

Each secret's value is mounted into the matching pod by the Secrets Store CSI Driver via a `SecretProviderClass`. The driver projects the value as the environment variable `ConnectionStrings__DefaultConnection`, which is the exact key the services already read (no application code changes required).

The RDS master-credentials secret managed by RDS itself is separate and used only by the bootstrap operator when creating the application databases.

### 3.6 S3 + CloudFront

- S3 bucket: `angular-micro-spa-<account-id>` (region: `us-east-1`)
- Block-public-access fully enabled
- Origin Access Control (OAC) restricts S3 reads to the CloudFront distribution principal
- CloudFront distribution with two origins:
  1. S3 bucket — default cache behavior, path pattern `/*`
  2. ALB DNS name — cache behavior on path pattern `/api/*`, caching disabled, all HTTP methods forwarded, viewer protocol policy `redirect-to-https`
- Custom error responses: 403 and 404 from S3 mapped to `/index.html` with HTTP 200 (Angular SPA history-mode routing)
- Domain: default `*.cloudfront.net`. Route 53 / ACM custom domain is out of scope.

### 3.7 IAM

- **GitHub OIDC identity provider** registered in the account (one-time, account-wide).
- **`gh-actions-deployer` role** — trust policy restricts to `repo:hitsshaa/AngularDotNetMicroservices:ref:refs/heads/main` (no PRs, no other branches). Permissions:
  - ECR: `GetAuthorizationToken`, push/pull on the three application repositories
  - EKS: `DescribeCluster` (for `aws eks update-kubeconfig`); cluster-side `kubectl` permissions granted via `aws-auth` ConfigMap or an EKS Access Entry mapping the role to a Kubernetes group with deploy permissions in `angular-micro`
  - S3: `PutObject`, `DeleteObject`, `ListBucket` on the SPA bucket only
  - CloudFront: `CreateInvalidation` on the distribution only
- **`eks-secrets-reader` IRSA role** — attached to the two service accounts in `angular-micro`. Permissions: `secretsmanager:GetSecretValue` and `kms:Decrypt` on the two application secrets only.

---

## 4. Application Code & Manifest Changes

### 4.1 Unchanged

- `src/ApiGateway/*` — Ocelot configuration in `ocelot.json` keeps the same downstream hosts (`user-service`, `product-service`); Kubernetes Service DNS resolves them inside the cluster
- `src/Microservices/UserService/*` and `src/Microservices/ProductService/*` — already read `ConnectionStrings__DefaultConnection` from the environment, which is exactly what the CSI driver will inject
- `src/ClientApp/src/app/*` — Angular components, services, models, interceptors all unchanged

### 4.2 Modified

- `src/ClientApp/src/environments/environment.prod.ts` — `apiUrl` becomes `/api` (relative). The SPA and API now share the same CloudFront origin.
- `k8s/user-service.yaml`
  - Remove the `envFrom: secretRef: { name: user-service-secret }` block
  - Add `serviceAccountName: user-service-sa`
  - Add a CSI volume referencing `SecretProviderClass: user-service-db`
  - Add a `volumeMount` so the projected secret materializes as the `ConnectionStrings__DefaultConnection` env var
- `k8s/product-service.yaml` — same shape of changes as user-service
- `k8s/api-gateway.yaml` — Service type stays `ClusterIP`. The frontend is no longer in-cluster, so no NodePort or LoadBalancer service is needed here; traffic reaches the gateway through the ALB Ingress defined in `k8s/ingress-alb.yaml`.

### 4.3 Deleted

- `k8s/angular-client.yaml` — Angular ships to S3 now
- `k8s/nodeport.yaml` — replaced by ALB
- `k8s/ingress.yaml` (NGINX Ingress flavour) — replaced by ALB Ingress
- `k8s/sql-server.yaml` and `k8s/sqlserver-pv.yaml` — replaced by RDS
- `k8s/Jobs/init-database-job.yaml` — bootstrap creates the two databases once on RDS; EF Core auto-migration at service startup handles tables (per `DOCUMENTATION.md:142`). The two existing migration jobs (`init-user-migrations.yaml`, `init-product-migrations.yaml`) are also dropped for the same reason — auto-migration on startup covers them.

### 4.4 New Files

- `aws/eksctl-cluster.yaml` — declarative cluster + VPC + node group definition consumed by `eksctl create cluster`
- `aws/iam/github-oidc-trust-policy.json` — trust policy for the `gh-actions-deployer` role
- `aws/iam/gh-actions-deployer-policy.json` — permissions policy attached to that role
- `aws/iam/eks-secrets-reader-policy.json` — permissions policy for the IRSA role attached to the two service accounts
- `aws/cloudfront-distribution.json` — distribution config for `aws cloudfront create-distribution`
- `aws/bootstrap.sh` — orchestrates the one-time setup in Section 5; idempotent where feasible
- `aws/teardown.sh` — reverse order of bootstrap to remove all paid resources
- `aws/README.md` — operator instructions
- `k8s/secret-provider-class-user.yaml` and `k8s/secret-provider-class-product.yaml` — bind the AWS provider to the two Secrets Manager secrets
- `k8s/serviceaccount-user.yaml` and `k8s/serviceaccount-product.yaml` — IRSA-annotated service accounts
- `k8s/ingress-alb.yaml` — a single Ingress fronting the `api-gateway` Service, annotated for the AWS Load Balancer Controller (`kubernetes.io/ingress.class: alb`, `alb.ingress.kubernetes.io/scheme: internet-facing`, `alb.ingress.kubernetes.io/target-type: ip`)

---

## 5. Bootstrap (One-Time Manual Steps)

Documented in `aws/README.md` and partly automated by `aws/bootstrap.sh`. Order matters because later steps reference earlier outputs.

1. **GitHub OIDC provider** — `aws iam create-open-id-connect-provider` for `https://token.actions.githubusercontent.com`. One per AWS account.
2. **`gh-actions-deployer` IAM role** — trust policy locked to `repo:hitsshaa/AngularDotNetMicroservices:ref:refs/heads/main`; attach the deployer permissions policy. Record the role ARN.
3. **ECR repos** — `aws ecr create-repository` for each of the three application services; apply the keep-last-10 lifecycle policy.
4. **VPC + EKS cluster** — `eksctl create cluster -f aws/eksctl-cluster.yaml`. Takes ~15 minutes. Creates the VPC, both subnet tiers, NAT, control plane, and the node group in one go.
5. **EKS add-ons**
   - `eksctl create iamserviceaccount` for the AWS Load Balancer Controller, then `helm install aws-load-balancer-controller`
   - `helm install` Secrets Store CSI Driver + AWS provider
   - EBS CSI driver as a managed add-on
6. **RDS instance** — `aws rds create-db-instance` in the private subnets, with the EKS-node security group permitted on 1433. Wait for `available`. From a temporary in-cluster pod or a bastion, connect once with the admin credentials and run `CREATE DATABASE UserServiceDB; CREATE DATABASE ProductServiceDB;`. EF Core handles the schema on first service startup.
7. **AWS Secrets Manager** — `aws secretsmanager create-secret` for the two application secrets, each containing the full connection string built from the RDS endpoint and the master password from the RDS-managed credentials secret.
8. **IRSA service accounts** — `eksctl create iamserviceaccount` for `user-service-sa` and `product-service-sa` in `angular-micro`, attached to the `eks-secrets-reader` policy scoped to just the two application secret ARNs.
9. **S3 bucket** — `aws s3 mb` with the SPA bucket name, enable Block Public Access, apply the OAC-only bucket policy (added in step 10).
10. **CloudFront distribution** — `aws cloudfront create-distribution --distribution-config file://aws/cloudfront-distribution.json`. Record the distribution ID and the `*.cloudfront.net` URL.
11. **GitHub repository variables** — set `AWS_ACCOUNT_ID` and `CLOUDFRONT_DISTRIBUTION_ID` under repo Settings → Variables.

After step 11, every push to `main` triggers a full automated deploy.

---

## 6. CI/CD Workflow Shape

Extend `.github/workflows/ci-cd.yml`. The existing backend and frontend test jobs stay. The existing `docker` job that pushed to GHCR is replaced.

### Jobs

- **`aws-auth`** — once per run. Uses `aws-actions/configure-aws-credentials@v4` with `role-to-assume` referencing `gh-actions-deployer` and `aws-region: us-east-1`. No long-lived AWS keys.
- **`backend-deploy`** (needs `backend`, `aws-auth`)
  1. `aws ecr get-login-password | docker login ...`
  2. Build & push the three images, tagged with both `latest` and `${{ github.sha }}`
  3. `aws eks update-kubeconfig --name angular-micro-eks --region us-east-1`
  4. `kubectl apply -f k8s/` — after Section 4.3 deletions, the directory contains only manifests the cluster should hold (namespace, api-gateway, user-service, product-service, ingress-alb, secret-provider-classes, service accounts)
  5. `kubectl set image deployment/<svc> <svc>=<ecr-uri>:${{ github.sha }} -n angular-micro` for each service — forces a rollout on every commit
  6. `kubectl rollout status deployment/<svc> -n angular-micro --timeout=5m` for each — fails the job if any pod fails to come up
- **`frontend-deploy`** (needs `frontend`, `aws-auth`)
  1. `cd src/ClientApp && npm ci && npm run build -- --configuration production`
  2. `aws s3 sync dist/client-app/browser/ s3://angular-micro-spa-<account-id>/ --delete`
  3. `aws cloudfront create-invalidation --distribution-id <id> --paths "/*"`

### Triggers

- `push` to `main` → all jobs run (test + deploy)
- Pull requests → test jobs only, no deploy
- Concurrency group `aws-deploy-${{ github.ref }}` prevents overlapping deploys on the same branch

### Repository configuration

- Variables: `AWS_ACCOUNT_ID`, `CLOUDFRONT_DISTRIBUTION_ID`
- Secrets: none (OIDC replaces them)

---

## 7. Verification

Run after the first end-to-end deploy completes:

- `kubectl get pods -n angular-micro` — all pods `Running` with 0 restarts
- `kubectl logs -n angular-micro deploy/user-service | grep -i migration` — confirm EF Core migrations applied successfully against RDS
- `kubectl logs -n angular-micro deploy/product-service | grep -i migration` — same for ProductService
- `curl https://<cloudfront-domain>/api/users` — returns the three seeded users (Alice, Bob, Charlie)
- `curl https://<cloudfront-domain>/api/products` — returns the five seeded products (Keyboard, Mouse, Monitor, Dock, Headset)
- Open `https://<cloudfront-domain>/` in a browser — Angular SPA loads, `/users` and `/products` routes work, CRUD via the UI succeeds
- `kubectl exec` into any service pod and confirm `printenv ConnectionStrings__DefaultConnection` shows the RDS endpoint, not the local one — proves the CSI driver mount is working

---

## 8. Teardown

`aws/teardown.sh` reverses bootstrap to keep cost at zero between learning sessions:

1. Disable CloudFront distribution, wait for `Deployed` state, then delete it
2. Empty and delete the S3 bucket
3. Delete the IRSA service accounts (`eksctl delete iamserviceaccount`)
4. Delete the two application secrets in Secrets Manager
5. Delete the RDS instance with `--skip-final-snapshot`
6. `eksctl delete cluster --name angular-micro-eks` — also tears down the VPC, NAT Gateway, subnets, and node group
7. Delete the three ECR repositories
8. Delete the `gh-actions-deployer` IAM role and its policies
9. (Optional, only if no other repo uses it) Delete the GitHub OIDC provider

---

## 9. Cost Estimate

Rough monthly cost in `us-east-1` with everything running on-demand 24/7:

| Resource | Approx. monthly |
|---|---|
| EKS control plane | ~$73 |
| 2 × t3.medium worker nodes | ~$60 |
| NAT Gateway (incl. data) | ~$35 |
| RDS db.t3.small SQL Server Express | ~$30 |
| Application Load Balancer | ~$18 |
| CloudFront + S3 + ECR + Secrets Manager | < $5 |
| **Total if always-on** | **~$220/month (~$8/day)** |

With disciplined teardown between sessions, expected actual cost is in single-digit dollars per month.

---

## 10. Non-Goals (Explicitly Out of Scope)

To keep the plan focused, the following are deferred:

- Authentication / authorization (JWT, IdP, etc.)
- Redis caching wiring
- OpenTelemetry / Prometheus / Grafana / Loki
- xUnit and Jasmine/Playwright test suites
- Custom domain + Route 53 + ACM certificate
- Multi-AZ RDS, blue/green deploys, autoscaling beyond defaults
- Migrating SQL Server to PostgreSQL/Aurora
- IaC (Terraform/CDK) — bootstrap uses scripted AWS CLI + `eksctl`; converting to IaC is a follow-up

---

## 11. References

- `DOCUMENTATION.md` — current architecture and roadmap
- `k8s/` — existing Kubernetes manifests being adapted
- `.github/workflows/ci-cd.yml` — existing CI/CD workflow being extended
- `src/ClientApp/src/environments/environment.prod.ts` — frontend API base URL
- `src/Microservices/UserService/Data/UserDbContext.cs` and `src/Microservices/ProductService/Data/ProductDbContext.cs` — DbContexts whose connection strings now come from Secrets Manager
