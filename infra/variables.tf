variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the deployer role (owner/repo)"
  type        = string
  default     = "Hitsshaa/MicroservicesApp"
}

variable "github_branch" {
  description = "Git branch allowed to deploy via OIDC"
  type        = string
  default     = "main"
}

variable "rds_admin_username" {
  description = "RDS master username"
  type        = string
  default     = "sqladmin"
}

variable "rds_admin_password" {
  description = "RDS master password (must be 8-128 chars; mix of upper/lower/digit/symbol)"
  type        = string
  sensitive   = true
}

variable "node_instance_type" {
  description = "EC2 instance type for the EKS managed node group"
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "rds_instance_class" {
  description = "RDS instance class (SQL Server Express minimum is db.t3.small)"
  type        = string
  default     = "db.t3.small"
}

variable "rds_allocated_storage_gb" {
  description = "RDS allocated storage in GiB"
  type        = number
  default     = 20
}

variable "skip_cloudfront" {
  description = "On first apply set this to true so CloudFront can wait until after the ALB exists. Then push k8s manifests, then re-apply with this false."
  type        = bool
  default     = true
}
