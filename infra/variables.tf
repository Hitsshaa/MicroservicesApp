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
  default     = "postgres"
}

variable "rds_admin_password" {
  description = "RDS master password (must be 8-128 chars; mix of upper/lower/digit/symbol)"
  type        = string
  sensitive   = true
}

variable "rds_instance_class" {
  description = "RDS instance class (db.t3.micro is free-tier eligible for PostgreSQL)"
  type        = string
  default     = "db.t3.micro"
}

variable "rds_allocated_storage_gb" {
  description = "RDS allocated storage in GiB (free tier covers 20 GiB)"
  type        = number
  default     = 20
}

variable "task_cpu" {
  description = "Fargate task CPU units (256 = .25 vCPU, smallest, cheapest)"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory MiB (512 is the minimum for cpu=256)"
  type        = number
  default     = 512
}

variable "use_fargate_spot" {
  description = "Run ECS tasks on Fargate Spot (~70% cheaper, can be interrupted). Safe for learning."
  type        = bool
  default     = true
}

variable "service_desired_count" {
  description = "Desired running count per ECS service. Set to 0 to scale to zero between learning sessions."
  type        = number
  default     = 1
}

variable "skip_cloudfront" {
  description = "On first apply, set true so CloudFront can wait until after the ALB exists. Then re-apply with this false."
  type        = bool
  default     = true
}
