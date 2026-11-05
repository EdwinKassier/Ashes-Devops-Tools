# Resource-assertion tests for the aws/compute/ecs-fargate module.
#
# Asserts on configured attributes known at plan time under mock_provider —
# including the jsonencoded container_definitions, decoded back with jsondecode()
# to prove secrets are wired via valueFrom and never as plaintext.

mock_provider "aws" {}

variables {
  name               = "orders-api"
  region             = "eu-west-2"
  family             = "orders-api"
  cluster_arn        = "arn:aws:ecs:eu-west-2:123456789012:cluster/app"
  container_image    = "123456789012.dkr.ecr.eu-west-2.amazonaws.com/orders:1.0.0"
  container_port     = 8080
  subnets            = ["subnet-0aaa", "subnet-0bbb"]
  security_group_ids = ["sg-0aaa"]
  execution_role_arn = "arn:aws:iam::123456789012:role/orders-exec"
  task_role_arn      = "arn:aws:iam::123456789012:role/orders-task"
  container_secrets = [
    { name = "DB_PASSWORD", valueFrom = "arn:aws:secretsmanager:eu-west-2:123456789012:secret:orders/db-AbCdEf" }
  ]
}

run "secure_fargate_defaults" {
  command = plan

  assert {
    condition     = aws_ecs_service.this.launch_type == "FARGATE"
    error_message = "service must use the FARGATE launch type."
  }

  assert {
    condition     = aws_ecs_task_definition.this.network_mode == "awsvpc"
    error_message = "task definition must use awsvpc network mode (required for Fargate)."
  }

  assert {
    condition     = contains(tolist(aws_ecs_task_definition.this.requires_compatibilities), "FARGATE")
    error_message = "task definition must declare FARGATE compatibility."
  }

  # Secure default: no public IP.
  assert {
    condition     = aws_ecs_service.this.network_configuration[0].assign_public_ip == false
    error_message = "assign_public_ip must default to false (tasks run in private subnets)."
  }

  # Secure default: ECS Exec off.
  assert {
    condition     = aws_ecs_service.this.enable_execute_command == false
    error_message = "enable_execute_command must default to false."
  }

  # Secrets are injected via valueFrom ARNs — never plaintext.
  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].secrets[0].valueFrom == "arn:aws:secretsmanager:eu-west-2:123456789012:secret:orders/db-AbCdEf"
    error_message = "container secret must be wired via valueFrom pointing at a Secrets Manager ARN."
  }

  # awslogs driver shipping to CloudWatch.
  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].logConfiguration.logDriver == "awslogs"
    error_message = "container must use the awslogs log driver."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this.container_definitions)[0].image == "123456789012.dkr.ecr.eu-west-2.amazonaws.com/orders:1.0.0"
    error_message = "container image must match the supplied container_image."
  }

  # No load balancer and no autoscaling by default.
  assert {
    condition     = length(aws_ecs_service.this.load_balancer) == 0
    error_message = "no load_balancer block must be present when target_group_arn is empty."
  }

  assert {
    condition     = length(aws_appautoscaling_target.this) == 0
    error_message = "no autoscaling target must be created when enable_autoscaling is false."
  }

  assert {
    condition     = length(aws_ecs_cluster.this) == 0
    error_message = "no cluster must be created when create_cluster is false."
  }

  assert {
    condition     = output.log_group_name == "/ecs/orders-api"
    error_message = "log_group_name output must default to /ecs/<family>."
  }
}

run "load_balancer_and_autoscaling_enabled" {
  command = plan

  variables {
    target_group_arn   = "arn:aws:elasticloadbalancing:eu-west-2:123456789012:targetgroup/orders/abc123"
    enable_autoscaling = true
    autoscaling_max_capacity = 12
  }

  assert {
    condition     = length(aws_ecs_service.this.load_balancer) == 1
    error_message = "a load_balancer block must be present when target_group_arn is set."
  }

  assert {
    condition     = one(aws_ecs_service.this.load_balancer).container_port == var.container_port
    error_message = "load balancer container port must default to container_port."
  }

  assert {
    condition     = length(aws_appautoscaling_target.this) == 1
    error_message = "an autoscaling target must be created when enable_autoscaling is true."
  }

  assert {
    condition     = aws_appautoscaling_target.this[0].max_capacity == 12
    error_message = "autoscaling target max_capacity must reflect the supplied value."
  }

  assert {
    condition     = aws_appautoscaling_policy.cpu[0].policy_type == "TargetTrackingScaling"
    error_message = "autoscaling policy must be a target-tracking policy."
  }
}

run "cluster_and_log_group_created" {
  command = plan

  variables {
    create_cluster     = true
    cluster_arn        = ""
    create_log_group   = true
    log_retention_days = 90
  }

  assert {
    condition     = length(aws_ecs_cluster.this) == 1
    error_message = "a cluster must be created when create_cluster is true."
  }

  assert {
    condition     = one(aws_ecs_cluster.this[0].setting).value == "enabled"
    error_message = "the created cluster must enable Container Insights."
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.this) == 1
    error_message = "a log group must be created when create_log_group is true."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].retention_in_days == 90
    error_message = "the log group must use the supplied retention."
  }
}
