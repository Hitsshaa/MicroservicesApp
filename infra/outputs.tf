output "aws_account_id" {
  description = "AWS account ID — set this as a GitHub repo variable AWS_ACCOUNT_ID"
  value       = local.account_id
}

output "aws_region" {
  description = "Region everything was deployed into"
  value       = var.aws_region
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.this.name
}

output "ecr_registry_url" {
  description = "ECR registry URL — used by GitHub Actions to push images"
  value       = "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

output "ecr_repository_urls" {
  description = "Per-service ECR repository URLs"
  value       = { for k, v in aws_ecr_repository.app : k => v.repository_url }
}

output "rds_endpoint" {
  description = "RDS Postgres endpoint hostname"
  value       = aws_db_instance.postgres.address
}

output "alb_dns_name" {
  description = "ALB DNS name (the api-gateway entrypoint)"
  value       = aws_lb.api.dns_name
}

output "spa_bucket_name" {
  description = "S3 bucket holding the Angular SPA"
  value       = aws_s3_bucket.spa.bucket
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID — set this as a GitHub repo variable CLOUDFRONT_DISTRIBUTION_ID"
  value       = try(aws_cloudfront_distribution.spa[0].id, null)
}

output "cloudfront_domain_name" {
  description = "CloudFront *.cloudfront.net domain — open this in a browser after deploy"
  value       = try(aws_cloudfront_distribution.spa[0].domain_name, null)
}

output "gh_actions_deployer_role_arn" {
  description = "Role ARN GitHub Actions assumes via OIDC"
  value       = aws_iam_role.gh_actions_deployer.arn
}

output "next_steps" {
  description = "What to do after terraform apply succeeds"
  value       = <<EOT

================================================================
Terraform apply complete.

Resources:
  ECS cluster:        ${aws_ecs_cluster.this.name}
  RDS endpoint:       ${aws_db_instance.postgres.address}
  ALB:                ${aws_lb.api.dns_name}
  SPA bucket:         ${aws_s3_bucket.spa.bucket}

Manual finishing steps:

1. Create the two application databases on RDS (one-shot ECS task):
   The dotnet apps create their own tables via EnsureCreated(), but the
   databases themselves need to exist first. Run:

     aws rds describe-db-instances --db-instance-identifier angular-micro-postgres \
       --region ${var.aws_region}

   Then connect via your favorite psql client and:
     CREATE DATABASE userservicedb;
     CREATE DATABASE productservicedb;

   (Or just push to main — the next CI run will trigger the apps which
   will sit retrying until the DBs exist.)

2. Set these GitHub repo variables (Settings -> Secrets and variables -> Actions -> Variables):
     AWS_ACCOUNT_ID = ${local.account_id}
     CLOUDFRONT_DISTRIBUTION_ID = ${try(aws_cloudfront_distribution.spa[0].id, "<run second apply with skip_cloudfront=false>")}

3. Push to main to trigger CI/CD: image builds -> ECR -> aws ecs update-service.

4. After everything is running, visit:
     ${try("https://${aws_cloudfront_distribution.spa[0].domain_name}/", "<CloudFront skipped on first apply — see infra/README.md>")}
================================================================
EOT
}
