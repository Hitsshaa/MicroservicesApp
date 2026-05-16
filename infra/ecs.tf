# --------------------------------------------------------------------------
# CloudWatch log group — one per service
# --------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "service" {
  for_each = toset(local.ecr_services)

  name              = "/ecs/angular-micro/${each.key}"
  retention_in_days = 7
}

# --------------------------------------------------------------------------
# ECS cluster
# --------------------------------------------------------------------------
resource "aws_ecs_cluster" "this" {
  name = local.cluster_name

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = var.use_fargate_spot ? "FARGATE_SPOT" : "FARGATE"
    weight            = 1
    base              = 1
  }
}

# --------------------------------------------------------------------------
# Service Discovery (Cloud Map) — inter-service DNS so api-gateway can reach
# user-service and product-service by name, the same way it did in compose
# and EKS.
# --------------------------------------------------------------------------
resource "aws_service_discovery_private_dns_namespace" "this" {
  name        = "angular-micro.local"
  description = "Internal DNS for ECS services"
  vpc         = module.vpc.vpc_id
}

resource "aws_service_discovery_service" "service" {
  for_each = toset(local.ecr_services)

  name = each.key

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.this.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

# --------------------------------------------------------------------------
# Task execution role — used by ECS itself to pull images, write logs,
# and resolve Secrets Manager values into env vars before the container
# starts.
# --------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_task_exec_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${local.cluster_name}-task-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_exec_trust.json
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Allow the execution role to read the per-service secrets so it can inject
# them as env vars at task start.
data "aws_iam_policy_document" "task_exec_secrets" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      aws_secretsmanager_secret.user_db.arn,
      aws_secretsmanager_secret.product_db.arn,
    ]
  }
}

resource "aws_iam_role_policy" "task_exec_secrets" {
  name   = "secrets-read"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_exec_secrets.json
}

# --------------------------------------------------------------------------
# Task role — used by the running app process. Empty for now (the app
# itself doesn't need any AWS API access), but we attach an empty role
# so the inheritance chain is explicit.
# --------------------------------------------------------------------------
resource "aws_iam_role" "task" {
  name               = "${local.cluster_name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_exec_trust.json
}

# --------------------------------------------------------------------------
# Task definitions — one per service
# --------------------------------------------------------------------------
locals {
  service_secret_arns = {
    user-service    = aws_secretsmanager_secret.user_db.arn
    product-service = aws_secretsmanager_secret.product_db.arn
  }
}

resource "aws_ecs_task_definition" "service" {
  for_each = toset(local.ecr_services)

  family                   = each.key
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = each.key
      image     = "${aws_ecr_repository.app[each.key].repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = local.service_ports[each.key]
          hostPort      = local.service_ports[each.key]
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "ASPNETCORE_ENVIRONMENT", value = "Production" },
        { name = "ASPNETCORE_URLS", value = "http://+:${local.service_ports[each.key]}" }
      ]

      secrets = contains(keys(local.service_secret_arns), each.key) ? [
        {
          name      = "ConnectionStrings__DefaultConnection"
          valueFrom = local.service_secret_arns[each.key]
        }
      ] : []

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.service[each.key].name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

# --------------------------------------------------------------------------
# ECS services — one per app
# --------------------------------------------------------------------------
resource "aws_ecs_service" "user_service" {
  name            = "user-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.service["user-service"].arn
  desired_count   = var.service_desired_count
  launch_type     = null

  capacity_provider_strategy {
    capacity_provider = var.use_fargate_spot ? "FARGATE_SPOT" : "FARGATE"
    weight            = 1
    base              = 1
  }

  network_configuration {
    subnets          = module.vpc.public_subnets
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.service["user-service"].arn
  }

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}

resource "aws_ecs_service" "product_service" {
  name            = "product-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.service["product-service"].arn
  desired_count   = var.service_desired_count
  launch_type     = null

  capacity_provider_strategy {
    capacity_provider = var.use_fargate_spot ? "FARGATE_SPOT" : "FARGATE"
    weight            = 1
    base              = 1
  }

  network_configuration {
    subnets          = module.vpc.public_subnets
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_service.service["product-service"].arn
  }

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}

resource "aws_ecs_service" "api_gateway" {
  name            = "api-gateway"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.service["api-gateway"].arn
  desired_count   = var.service_desired_count
  launch_type     = null

  capacity_provider_strategy {
    capacity_provider = var.use_fargate_spot ? "FARGATE_SPOT" : "FARGATE"
    weight            = 1
    base              = 1
  }

  network_configuration {
    subnets          = module.vpc.public_subnets
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api_gateway.arn
    container_name   = "api-gateway"
    container_port   = 5000
  }

  service_registries {
    registry_arn = aws_service_discovery_service.service["api-gateway"].arn
  }

  depends_on = [aws_lb_listener.api_http]

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}
