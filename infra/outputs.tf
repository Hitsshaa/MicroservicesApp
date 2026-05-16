output "aws_account_id" {
  description = "AWS account ID — set this as a GitHub repo variable AWS_ACCOUNT_ID"
  value       = local.account_id
}

output "aws_region" {
  description = "Region everything was deployed into"
  value       = var.aws_region
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
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
  description = "RDS SQL Server endpoint hostname"
  value       = aws_db_instance.sqlserver.address
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

output "user_service_irsa_role_arn" {
  description = "IRSA role for user-service pods (read user-service secret)"
  value       = aws_iam_role.user_service_irsa.arn
}

output "product_service_irsa_role_arn" {
  description = "IRSA role for product-service pods (read product-service secret)"
  value       = aws_iam_role.product_service_irsa.arn
}

output "next_steps" {
  description = "What to do after terraform apply succeeds"
  value       = <<EOT

================================================================
Terraform apply complete. Manual finishing steps:

1. Update kubeconfig so kubectl can talk to the new cluster:
     aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}

2. Create the two application databases on RDS:
     kubectl create ns ${local.namespace} 2>$null
     kubectl run sqlcmd-init --rm -i --restart=Never --image=mcr.microsoft.com/mssql-tools -n ${local.namespace} -- \
       /opt/mssql-tools/bin/sqlcmd -S ${aws_db_instance.sqlserver.address} -U ${var.rds_admin_username} -P '<your password>' \
       -Q "IF DB_ID('UserServiceDB') IS NULL CREATE DATABASE UserServiceDB; IF DB_ID('ProductServiceDB') IS NULL CREATE DATABASE ProductServiceDB;"

3. Substitute IRSA ARNs into the k8s service account manifests:
     # In k8s/serviceaccount-user.yaml replace PLACEHOLDER_EKS_SECRETS_READER_ROLE_ARN with:
     #   ${aws_iam_role.user_service_irsa.arn}
     # In k8s/serviceaccount-product.yaml replace with:
     #   ${aws_iam_role.product_service_irsa.arn}

4. Set these GitHub repo variables (Settings -> Secrets and variables -> Actions -> Variables):
     AWS_ACCOUNT_ID = ${local.account_id}
     CLOUDFRONT_DISTRIBUTION_ID = ${try(aws_cloudfront_distribution.spa[0].id, "<run second apply with skip_cloudfront=false>")}

5. Push to main to trigger the first deploy.

6. After everything is running, visit:
     ${try("https://${aws_cloudfront_distribution.spa[0].domain_name}/", "<CloudFront skipped on first apply — see infra/README.md>")}
================================================================
EOT
}
