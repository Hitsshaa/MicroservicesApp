resource "aws_security_group" "rds" {
  name        = "${local.cluster_name}-rds-sg"
  description = "Allow 5432 from ECS tasks only"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_tasks" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.tasks.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "Postgres access from ECS tasks"
}

resource "aws_db_subnet_group" "rds" {
  name       = "${local.cluster_name}-db-subnets"
  subnet_ids = module.vpc.public_subnets
}

resource "aws_db_instance" "postgres" {
  identifier = "angular-micro-postgres"

  engine            = "postgres"
  engine_version    = "16.4"
  instance_class    = var.rds_instance_class
  allocated_storage = var.rds_allocated_storage_gb
  storage_type      = "gp2"
  storage_encrypted = true

  db_name  = "appdb"
  username = var.rds_admin_username
  password = var.rds_admin_password

  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period = 0
  skip_final_snapshot     = true
  apply_immediately       = true
  deletion_protection     = false
}
