# ECS Fargate service for the landing zone.
#
# Composes a Fargate task definition + service with secure defaults:
#   - launch_type FARGATE, awsvpc network mode, tasks in PRIVATE subnets
#   - no public IP by default, ECS Exec off by default
#   - secrets injected via valueFrom (Secrets Manager / SSM ARNs), never plaintext
#   - awslogs driver shipping to a CloudWatch log group with retention + optional KMS
#
# Everything is a toggle: the cluster is either created here (create_cluster, with
# Container Insights on) or passed in; the log group is created here or passed in;
# ALB registration and Application Auto Scaling are both opt-in. Set
# enable_external_deployments when a CI pipeline rolls task definition revisions,
# so Terraform stops reverting them (see the service variants below).
#
# IAM roles (execution + task) are accepted as ARNs — least-privilege scoping is
# the caller's responsibility, so this module never mints permissive roles.

locals {
  cluster_arn = var.create_cluster ? aws_ecs_cluster.this[0].arn : var.cluster_arn

  # Application Auto Scaling resource_id needs the cluster NAME, not its ARN.
  # An ECS cluster ARN is arn:aws:ecs:<region>:<acct>:cluster/<name>, so the
  # name is the segment after the final "/".
  cluster_name = var.create_cluster ? var.name : element(split("/", var.cluster_arn), length(split("/", var.cluster_arn)) - 1)

  container_name = var.container_name != "" ? var.container_name : var.name
  log_group_name = var.log_group_name != "" ? var.log_group_name : "/ecs/${var.family}"
  lb_port        = var.load_balancer_container_port != null ? var.load_balancer_container_port : var.container_port
  attach_lb      = var.target_group_arn != ""

  # Single primary container. Secrets use valueFrom (ARN references) so no secret
  # material is ever embedded in the task definition or Terraform state.
  container_definitions = [
    {
      name      = local.container_name
      image     = var.container_image
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]
      environment = [for e in var.container_environment : { name = e.name, value = e.value }]
      secrets     = [for s in var.container_secrets : { name = s.name, valueFrom = s.valueFrom }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = local.log_group_name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = local.container_name
        }
      }
    }
  ]
}

# ── Cluster (optional) ────────────────────────────────────────────────────────

resource "aws_ecs_cluster" "this" {
  count = var.create_cluster ? 1 : 0

  name = var.name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = var.tags
}

# ── Log group ─────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "this" {
  count = var.create_log_group ? 1 : 0

  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_kms_key_arn == "" ? null : var.log_kms_key_arn

  tags = var.tags
}

# ── Task definition ───────────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "this" {
  family                   = var.family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    cpu_architecture        = var.cpu_architecture
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode(local.container_definitions)

  tags = var.tags
}

# ── Service ───────────────────────────────────────────────────────────────────
#
# Two mutually exclusive variants, selected by enable_external_deployments
# (lifecycle.ignore_changes cannot be conditional):
#   - this                : Terraform owns the running task definition revision.
#   - externally_deployed : a CI pipeline (e.g. GitHub Actions
#                           RegisterTaskDefinition + UpdateService) rolls new
#                           revisions, so Terraform ignores task_definition and
#                           desired_count instead of reverting every deploy /
#                           autoscaling decision on the next apply.

resource "aws_ecs_service" "this" {
  count = var.enable_external_deployments ? 0 : 1

  name            = var.name
  cluster         = local.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  propagate_tags  = "SERVICE"

  enable_execute_command = var.enable_execute_command

  health_check_grace_period_seconds = local.attach_lb ? var.health_check_grace_period_seconds : null

  # Roll back automatically when a new revision never becomes healthy.
  deployment_circuit_breaker {
    enable   = var.enable_deployment_circuit_breaker
    rollback = var.enable_deployment_circuit_breaker
  }

  network_configuration {
    subnets          = var.subnets
    security_groups  = var.security_group_ids
    assign_public_ip = var.assign_public_ip
  }

  dynamic "load_balancer" {
    for_each = local.attach_lb ? [1] : []
    content {
      target_group_arn = var.target_group_arn
      container_name   = local.container_name
      container_port   = local.lb_port
    }
  }

  tags = var.tags
}

resource "aws_ecs_service" "externally_deployed" {
  count = var.enable_external_deployments ? 1 : 0

  name            = var.name
  cluster         = local.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  propagate_tags  = "SERVICE"

  enable_execute_command = var.enable_execute_command

  health_check_grace_period_seconds = local.attach_lb ? var.health_check_grace_period_seconds : null

  deployment_circuit_breaker {
    enable   = var.enable_deployment_circuit_breaker
    rollback = var.enable_deployment_circuit_breaker
  }

  network_configuration {
    subnets          = var.subnets
    security_groups  = var.security_group_ids
    assign_public_ip = var.assign_public_ip
  }

  dynamic "load_balancer" {
    for_each = local.attach_lb ? [1] : []
    content {
      target_group_arn = var.target_group_arn
      container_name   = local.container_name
      container_port   = local.lb_port
    }
  }

  tags = var.tags

  lifecycle {
    # CI owns the running revision and (with autoscaling) the task count.
    ignore_changes = [task_definition, desired_count]
  }
}

# The service moved from a singleton to a count-gated resource.
moved {
  from = aws_ecs_service.this
  to   = aws_ecs_service.this[0]
}

locals {
  service = var.enable_external_deployments ? aws_ecs_service.externally_deployed[0] : aws_ecs_service.this[0]
}

# ── Autoscaling (optional) ────────────────────────────────────────────────────

resource "aws_appautoscaling_target" "this" {
  count = var.enable_autoscaling ? 1 : 0

  max_capacity       = var.autoscaling_max_capacity
  min_capacity       = var.autoscaling_min_capacity
  resource_id        = "service/${local.cluster_name}/${local.service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  count = var.enable_autoscaling ? 1 : 0

  name               = "${var.name}-cpu-tracking"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this[0].resource_id
  scalable_dimension = aws_appautoscaling_target.this[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.this[0].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = var.autoscaling_target_cpu

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
