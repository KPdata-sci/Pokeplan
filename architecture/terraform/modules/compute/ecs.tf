# Long-running services: dagster-webserver, dagster-daemon, metabase.
# Run-once tasks: ingest and transform. Dagster's EcsRunLauncher starts one per
# run with the task definition below, so each run gets its own container and role.

data "aws_region" "current" {}

locals {
  repo      = { for k, r in aws_ecr_repository.this : k => r.repository_url }
  db_secret = aws_db_instance.this.master_user_secret[0].secret_arn

  pipeline_env = merge(var.pipeline_env, {
    ECS_CLUSTER           = aws_ecs_cluster.this.name
    ECS_SUBNETS           = join(",", var.app_subnet_ids)
    ECS_SECURITY_GROUP    = aws_security_group.pipeline.id
    INGEST_TASK_FAMILY    = "${var.name}-ingest"
    TRANSFORM_TASK_FAMILY = "${var.name}-transform"
    DAGSTER_PG_HOST       = aws_db_instance.this.address
    DAGSTER_PG_DB         = "dagster"
  })
  env_list = [for k, v in local.pipeline_env : { name = k, value = v }]

  db_secrets = [
    { name = "DB_USERNAME", valueFrom = "${local.db_secret}:username::" },
    { name = "DB_PASSWORD", valueFrom = "${local.db_secret}:password::" },
  ]

  log = { for k in ["dagster", "metabase", "ingest", "transform"] : k => {
    logDriver = "awslogs"
    options = {
      awslogs-group         = aws_cloudwatch_log_group.this[k].name
      awslogs-region        = data.aws_region.current.name
      awslogs-stream-prefix = k
    }
  } }
}

resource "aws_ecs_cluster" "this" {
  name = var.name
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

resource "aws_cloudwatch_log_group" "this" {
  for_each          = toset(["dagster", "metabase", "ingest", "transform"])
  name              = "/ecs/${var.name}/${each.key}"
  retention_in_days = var.log_retention_days
}

# ---------- task definitions ----------

resource "aws_ecs_task_definition" "dagster" {
  for_each                 = { webserver = ["dagster-webserver", "-h", "0.0.0.0", "-p", "3000", "-w", "workspace.yaml"], daemon = ["dagster-daemon", "run", "-w", "workspace.yaml"] }
  family                   = "${var.name}-dagster-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arns["dagster"]
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([{
    name                   = "dagster-${each.key}"
    image                  = "${local.repo["dagster"]}:${var.image_tag}"
    command                = each.value
    essential              = true
    readonlyRootFilesystem = false
    portMappings           = each.key == "webserver" ? [{ containerPort = 3000 }] : []
    environment            = local.env_list
    secrets                = local.db_secrets
    logConfiguration       = local.log["dagster"]
  }])
}

resource "aws_ecs_task_definition" "pipeline" {
  for_each                 = { ingest = 1024, transform = 2048 }
  family                   = "${var.name}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = each.value
  memory                   = each.value * 4
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arns[each.key]
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  # Dagster overrides the command per run (dagster api execute_run ...).
  container_definitions = jsonencode([{
    name             = "run"
    image            = "${local.repo["pipeline"]}:${var.image_tag}"
    essential        = true
    environment      = local.env_list
    secrets          = local.db_secrets
    logConfiguration = local.log[each.key]
  }])
}

resource "aws_ecs_task_definition" "metabase" {
  family                   = "${var.name}-metabase"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arns["metabase"]

  container_definitions = jsonencode([{
    name         = "metabase"
    image        = "${local.repo["metabase"]}:${var.metabase_version}"
    essential    = true
    portMappings = [{ containerPort = 3000 }]
    environment = [
      { name = "MB_DB_TYPE", value = "postgres" },
      { name = "MB_DB_CONNECTION_URI", value = "postgres://${aws_db_instance.this.address}:5432/metabase?ssl=true&sslmode=require" },
      { name = "MB_SITE_URL", value = "https://metabase.${var.domain}" },
    ]
    secrets = [
      { name = "MB_DB_USER", valueFrom = "${local.db_secret}:username::" },
      { name = "MB_DB_PASS", valueFrom = "${local.db_secret}:password::" },
    ]
    logConfiguration = local.log["metabase"]
  }])
}

# ---------- services ----------

resource "aws_ecs_service" "dagster" {
  for_each        = aws_ecs_task_definition.dagster
  name            = "dagster-${each.key}"
  cluster         = aws_ecs_cluster.this.id
  task_definition = each.value.arn
  desired_count   = var.dagster_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.app_subnet_ids
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = each.key == "webserver" ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.this["dagster"].arn
      container_name   = "dagster-webserver"
      container_port   = 3000
    }
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
}

resource "aws_ecs_service" "metabase" {
  name            = "metabase"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.metabase.arn
  desired_count   = var.metabase_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.app_subnet_ids
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this["metabase"].arn
    container_name   = "metabase"
    container_port   = 3000
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
}
