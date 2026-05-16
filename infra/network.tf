data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs            = slice(data.aws_availability_zones.available.names, 0, 2)
  vpc_cidr       = "10.0.0.0/16"
  public_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
}

# Free-tier-friendly VPC: public subnets only, no NAT Gateway.
# Fargate tasks get public IPs and reach the internet through the IGW.
# This is acceptable for a learning environment; production would use
# private subnets + NAT, accepting the $35/mo NAT charge.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "${local.cluster_name}-vpc"
  cidr = local.vpc_cidr
  azs  = local.azs

  public_subnets       = local.public_subnets
  enable_nat_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true
}

# Application Load Balancer SG — open 80 to the world
resource "aws_security_group" "alb" {
  name        = "${local.cluster_name}-alb-sg"
  description = "Public ALB"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "alb_http_v4" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_egress" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# Tasks SG — only ALB can hit the gateway; services can talk to each other.
resource "aws_security_group" "tasks" {
  name        = "${local.cluster_name}-tasks-sg"
  description = "ECS tasks"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "tasks_from_alb" {
  security_group_id            = aws_security_group.tasks.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 5000
  to_port                      = 5000
  description                  = "ALB to api-gateway"
}

resource "aws_vpc_security_group_ingress_rule" "tasks_intra" {
  security_group_id            = aws_security_group.tasks.id
  referenced_security_group_id = aws_security_group.tasks.id
  ip_protocol                  = "tcp"
  from_port                    = 0
  to_port                      = 65535
  description                  = "Inter-service traffic"
}

resource "aws_vpc_security_group_egress_rule" "tasks_egress" {
  security_group_id = aws_security_group.tasks.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}
