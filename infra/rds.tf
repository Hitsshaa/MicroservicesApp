resource "aws_security_group" "rds" {
  name        = "${local.cluster_name}-rds-sg"
  description = "Allow 1433 from EKS node group only"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_eks" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = module.eks.node_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 1433
  to_port                      = 1433
  description                  = "SQL Server access from EKS worker nodes"
}

resource "aws_db_subnet_group" "rds" {
  name       = "${local.cluster_name}-db-subnets"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_db_instance" "sqlserver" {
  identifier = "angular-micro-sqlserver"

  engine               = "sqlserver-ex"
  engine_version       = "16.00.4085.2.v1"
  instance_class       = var.rds_instance_class
  license_model        = "license-included"
  allocated_storage    = var.rds_allocated_storage_gb
  storage_type         = "gp3"
  storage_encrypted    = true

  username             = var.rds_admin_username
  password             = var.rds_admin_password

  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period = 0
  skip_final_snapshot     = true
  apply_immediately       = true
  deletion_protection     = false

  # Application databases are created post-apply with a one-shot kubectl run.
  # See infra/README.md "After apply" section.
}
