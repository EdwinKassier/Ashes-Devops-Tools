# aws-app-services stage — the AWS application golden path
#
# Turns the empty workload spoke into somewhere a service team can ship. A team
# adds ONE entry to var.services and gets, in this workload account:
#
#   - ECR repository        — immutable tags, scan on push, KMS (data/ecr)
#   - CloudWatch log group  — KMS-encrypted, retention-bounded
#   - task execution role   — pull ITS repo, write ITS log group, read ITS secrets
#   - task role             — empty by default; the app's own permissions only
#   - Fargate service       — private subnets, no public IP, circuit breaker,
#                             behind the shared ALB (compute/ecs-fargate)
#   - GitHub deploy role    — optional (github + enable_github_oidc): OIDC trust
#                             pinned to aud=sts.amazonaws.com and an EXACT sub
#                             (immutable repository_id-based when IDs are set);
#                             can push to ITS repo, roll ITS service, and pass
#                             ONLY its own task roles
#   - Aurora PostgreSQL     — optional (database): RDS-managed master secret,
#                             isolated subnets, SG reachable only from the
#                             service's SG (data/rds-aurora)
#   - CloudWatch alarms     — optional (enable_alarms): CPU, memory, unhealthy
#                             targets, target 5xx (ops/cloudwatch)
#
# Shared per environment, created only when var.services is non-empty: one ECS
# cluster (Container Insights) and one ALB (internal by default) with a 404
# default action and host/path rules per service (network/load-balancer).
#
# The account-wide GitHub OIDC provider is created once per account when
# enable_github_oidc (and create_github_oidc_provider) are true.
#
# Default (services = {}, enable_github_oidc = false) creates NOTHING.
#
# All IAM policy JSON is built with jsonencode() (never
# data.aws_iam_policy_document) so trust and permission policies stay assertable
# under mock_provider.

locals {
  enabled = length(var.services) > 0

  cluster_name = "${var.environment}-apps"

  alb_subnet_ids    = length(var.alb_subnet_ids) > 0 ? var.alb_subnet_ids : var.service_subnet_ids
  alb_ingress_cidrs = length(var.alb_ingress_cidrs) > 0 ? var.alb_ingress_cidrs : [var.vpc_cidr]
  https             = var.alb_certificate_arn != null

  # The listener that carries the per-service routing rules.
  routing_listener = local.https ? "https" : "http"
  alb_ports        = local.https ? [80, 443] : [80]

  service_keys = sort(keys(var.services))

  # Per-service derived values.
  svc = {
    for k, s in var.services : k => {
      family         = "${var.environment}-${k}"
      log_group_name = "/ecs/${var.environment}/${k}"
      target_group   = "${var.environment}-${k}"
      priority       = coalesce(s.priority, 1000 + index(local.service_keys, k))
      path_patterns = (
        length(s.host_headers) + length(s.path_patterns) == 0
        ? ["/${k}", "/${k}/*"]
        : s.path_patterns
      )
      # Secrets Manager valueFrom may carry a JSON-key suffix
      # (arn:...:secret:name-AbCdEf:key::); IAM needs the bare 7-field secret ARN.
      secretsmanager_arns = distinct([
        for arn in values(s.secrets) : join(":", slice(split(":", arn), 0, 7))
        if can(regex("^arn:aws[a-z-]*:secretsmanager:", arn))
      ])
      ssm_arns = [for arn in values(s.secrets) : arn if can(regex("^arn:aws[a-z-]*:ssm:", arn))]
    }
  }

  # Services that get a GitHub Actions deploy role.
  deploy_services = var.enable_github_oidc ? { for k, s in var.services : k => s if s.github != null } : {}

  # Exact OIDC subject per deploy role. AWS IAM can only condition on standard
  # claims (sub/aud), so immutable repository IDs are matched through GitHub's
  # customised sub claim template (include_claim_keys = repository_owner_id,
  # repository_id, context). Precedence: explicit subject > ID-based (when
  # repository_id is set; the default to use) > name-based repo:<org>/<repo>
  # (mutable — a renamed/transferred/re-created repo name inherits trust).
  # The trailing context is ref:<ref> when ref is set, else environment:<env>.
  github_context = {
    for k, s in local.deploy_services : k => (
      s.github.ref != null ? "ref:${s.github.ref}" : "environment:${coalesce(s.github.environment, var.environment)}"
    )
  }

  github_subjects = {
    for k, s in local.deploy_services : k => (
      s.github.subject != null ? s.github.subject :
      s.github.repository_id != null ? "repository_owner_id:${s.github.repository_owner_id}:repository_id:${s.github.repository_id}:${local.github_context[k]}" :
      "repo:${s.github.repository}:${local.github_context[k]}"
    )
  }

  database_services = { for k, s in var.services : k => s if s.database != null }

  github_oidc_provider_arn = (
    var.enable_github_oidc && var.create_github_oidc_provider
    ? try(aws_iam_openid_connect_provider.github[0].arn, null)
    : var.github_oidc_provider_arn
  )

  account_id = try(data.aws_caller_identity.current[0].account_id, null)
}

data "aws_caller_identity" "current" {
  count = local.enabled ? 1 : 0
}

# =============================================================================
# GitHub Actions OIDC provider — once per account
# =============================================================================

resource "aws_iam_openid_connect_provider" "github" {
  count = var.enable_github_oidc && var.create_github_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # thumbprint_list omitted: IAM validates GitHub's OIDC endpoint against its
  # own trusted CA library, so a pinned thumbprint is no longer required.

  tags = merge(var.tags, { Name = "github-actions" })
}

# =============================================================================
# Shared ECS cluster
# =============================================================================

resource "aws_ecs_cluster" "this" {
  count = local.enabled ? 1 : 0

  name = local.cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = var.tags
}

# =============================================================================
# ECR repositories
# =============================================================================

module "ecr" {
  source = "../../data/ecr"
  count  = local.enabled ? 1 : 0

  repositories = {
    for k, s in var.services : k => {
      image_tag_mutability       = "IMMUTABLE"
      scan_on_push               = true
      kms_key_arn                = var.kms_key_arn
      expire_untagged_after_days = 7
      keep_last_tagged_images    = 100
    }
  }

  tags = var.tags
}

# =============================================================================
# Log groups
# =============================================================================

resource "aws_cloudwatch_log_group" "service" {
  # checkov:skip=CKV_AWS_158:kms_key_id is var.kms_key_arn, which the kms_key_arn validation requires to be a CMK ARN whenever services (and so any log group) is non-empty; checkov only sees the empty-string default.
  for_each = var.services

  name              = local.svc[each.key].log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, { Service = each.key })
}

# =============================================================================
# IAM — task execution role (ECS agent) and task role (application)
# =============================================================================

locals {
  ecs_tasks_trust = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "EcsTasksAssume"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
      # Confused-deputy guard: only ECS acting for THIS account.
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })
}

resource "aws_iam_role" "execution" {
  for_each = var.services

  name               = "${var.environment}-${each.key}-exec"
  description        = "ECS task execution role for ${each.key} (image pull, logs, secrets)."
  assume_role_policy = local.ecs_tasks_trust

  tags = merge(var.tags, { Service = each.key })
}

resource "aws_iam_role_policy" "execution" {
  for_each = var.services

  name = "execution"
  role = aws_iam_role.execution[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          # GetAuthorizationToken has no resource-level permissions.
          Sid      = "EcrAuth"
          Effect   = "Allow"
          Action   = "ecr:GetAuthorizationToken"
          Resource = "*"
        },
        {
          Sid    = "EcrPullOwnRepo"
          Effect = "Allow"
          Action = [
            "ecr:BatchCheckLayerAvailability",
            "ecr:BatchGetImage",
            "ecr:GetDownloadUrlForLayer",
          ]
          Resource = module.ecr[0].repository_arns[each.key]
        },
        {
          Sid      = "WriteOwnLogGroup"
          Effect   = "Allow"
          Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
          Resource = "${aws_cloudwatch_log_group.service[each.key].arn}:*"
        },
      ],
      length(local.svc[each.key].secretsmanager_arns) + (each.value.database != null ? 1 : 0) > 0 ? [{
        Sid    = "ReadOwnSecrets"
        Effect = "Allow"
        Action = "secretsmanager:GetSecretValue"
        Resource = concat(
          local.svc[each.key].secretsmanager_arns,
          each.value.database != null ? [module.database[each.key].master_user_secret_arn] : [],
        )
      }] : [],
      length(local.svc[each.key].ssm_arns) > 0 ? [{
        Sid      = "ReadOwnParameters"
        Effect   = "Allow"
        Action   = "ssm:GetParameters"
        Resource = local.svc[each.key].ssm_arns
      }] : [],
      length(each.value.secrets) > 0 || each.value.database != null ? [{
        Sid      = "DecryptSecrets"
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = var.kms_key_arn
      }] : [],
    )
  })
}

resource "aws_iam_role" "task" {
  for_each = var.services

  name               = "${var.environment}-${each.key}-task"
  description        = "ECS task role for ${each.key} (application permissions only)."
  assume_role_policy = local.ecs_tasks_trust

  tags = merge(var.tags, { Service = each.key })
}

resource "aws_iam_role_policy" "task" {
  for_each = { for k, s in var.services : k => s if s.task_role_policy_json != null }

  name   = "application"
  role   = aws_iam_role.task[each.key].id
  policy = each.value.task_role_policy_json
}

resource "aws_iam_role_policy" "task_exec" {
  # ECS Exec needs the SSM message channels on the TASK role.
  for_each = { for k, s in var.services : k => s if s.enable_execute_command }

  name = "ecs-exec"
  role = aws_iam_role.task[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "EcsExecChannels"
      Effect = "Allow"
      Action = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task" {
  for_each = merge([
    for k, s in var.services : { for arn in s.task_role_managed_policy_arns : "${k}|${arn}" => { service = k, arn = arn } }
  ]...)

  role       = aws_iam_role.task[each.value.service].name
  policy_arn = each.value.arn
}

# =============================================================================
# IAM — GitHub Actions deploy role (one per service with github set)
# =============================================================================

resource "aws_iam_role" "deploy" {
  for_each = local.deploy_services

  name                 = "${var.environment}-${each.key}-deploy"
  description          = "GitHub Actions deploy role for ${each.key} (${each.value.github.repository})."
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "GitHubActionsOidc"
      Effect    = "Allow"
      Principal = { Federated = local.github_oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      # Exact-match both claims: the audience the configure-aws-credentials
      # action requests, and ONE repo + environment/ref (no wildcards).
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = local.github_subjects[each.key]
        }
      }
    }]
  })

  tags = merge(var.tags, { Service = each.key })
}

resource "aws_iam_role_policy" "deploy" {
  for_each = local.deploy_services

  name = "deploy"
  role = aws_iam_role.deploy[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrAuth"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "EcrPushOwnRepo"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeImages",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
        ]
        Resource = module.ecr[0].repository_arns[each.key]
      },
      {
        # Task-definition actions have no resource-level permissions.
        Sid      = "EcsTaskDefinitions"
        Effect   = "Allow"
        Action   = ["ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"]
        Resource = "*"
      },
      {
        Sid      = "EcsRollOwnService"
        Effect   = "Allow"
        Action   = ["ecs:DescribeServices", "ecs:UpdateService"]
        Resource = module.service[each.key].service_arn
      },
      {
        # Only this service's own roles, and only to ECS tasks.
        Sid      = "PassOwnTaskRoles"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = [aws_iam_role.execution[each.key].arn, aws_iam_role.task[each.key].arn]
        Condition = {
          StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" }
        }
      },
    ]
  })
}

# =============================================================================
# Security groups — ALB -> service -> database, each hop on one port only
# =============================================================================

resource "aws_vpc_security_group_ingress_rule" "alb" {
  for_each = local.enabled ? {
    for pair in setproduct(local.alb_ports, local.alb_ingress_cidrs) : "${pair[0]}|${pair[1]}" => { port = pair[0], cidr = pair[1] }
  } : {}

  security_group_id = module.alb[0].security_group_id
  description       = "Listener ${each.value.port} from ${each.value.cidr}"
  ip_protocol       = "tcp"
  from_port         = each.value.port
  to_port           = each.value.port
  cidr_ipv4         = each.value.cidr

  tags = var.tags
}

resource "aws_security_group" "service" {
  # checkov:skip=CKV2_AWS_5:Attached to the service's task ENIs through module.service[*].security_group_ids; checkov cannot follow the for_each module input.
  for_each = var.services

  name        = "${var.environment}-${each.key}-svc"
  description = "Fargate tasks of ${each.key}."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${var.environment}-${each.key}-svc", Service = each.key })
}

resource "aws_vpc_security_group_ingress_rule" "service_from_alb" {
  for_each = var.services

  security_group_id            = aws_security_group.service[each.key].id
  description                  = "Container port from the shared ALB"
  ip_protocol                  = "tcp"
  from_port                    = each.value.container_port
  to_port                      = each.value.container_port
  referenced_security_group_id = module.alb[0].security_group_id

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "service_https" {
  # HTTPS out (via the spoke's TGW default route -> central egress/inspection)
  # for ECR, CloudWatch Logs, Secrets Manager and the app's own HTTPS calls.
  for_each = var.services

  security_group_id = aws_security_group.service[each.key].id
  description       = "HTTPS egress (AWS APIs via central egress)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"

  tags = var.tags
}

resource "aws_vpc_security_group_egress_rule" "service_to_db" {
  for_each = local.database_services

  security_group_id            = aws_security_group.service[each.key].id
  description                  = "PostgreSQL to the service's own Aurora cluster"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.database[each.key].id

  tags = var.tags
}

resource "aws_security_group" "database" {
  # checkov:skip=CKV2_AWS_5:Attached to the Aurora cluster through module.database[*].security_group_ids; checkov cannot follow the for_each module input.
  for_each = local.database_services

  name        = "${var.environment}-${each.key}-db"
  description = "Aurora cluster of ${each.key}; reachable only from its service."
  vpc_id      = var.vpc_id

  # No egress rules: a database never initiates connections.
  tags = merge(var.tags, { Name = "${var.environment}-${each.key}-db", Service = each.key })
}

resource "aws_vpc_security_group_ingress_rule" "database_from_service" {
  for_each = local.database_services

  security_group_id            = aws_security_group.database[each.key].id
  description                  = "PostgreSQL from the ${each.key} service only"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.service[each.key].id

  tags = var.tags
}

# =============================================================================
# Shared ALB
# =============================================================================

module "alb" {
  source = "../../network/load-balancer"
  count  = local.enabled ? 1 : 0

  name                       = local.cluster_name
  vpc_id                     = var.vpc_id
  subnet_ids                 = local.alb_subnet_ids
  load_balancer_type         = "application"
  internal                   = var.alb_internal
  create_security_group      = true
  egress_cidr_blocks         = [var.vpc_cidr] # targets are Fargate tasks in this VPC
  enable_deletion_protection = var.alb_enable_deletion_protection
  drop_invalid_header_fields = true

  access_logs = var.alb_access_logs_bucket == null ? null : {
    bucket = var.alb_access_logs_bucket
    prefix = "alb/${var.environment}"
  }

  target_groups = {
    for k, s in var.services : k => {
      name        = local.svc[k].target_group
      port        = s.container_port
      protocol    = "HTTP"
      target_type = "ip" # Fargate awsvpc tasks register by IP
      health_check = {
        path    = s.health_check_path
        matcher = "200-399"
      }
    }
  }

  # Unrouted requests get a 404; plain HTTP redirects to HTTPS when a cert is set.
  listeners = local.https ? {
    https = {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = var.alb_certificate_arn
      default_action  = "fixed-response"
    }
    http = {
      port           = 80
      protocol       = "HTTP"
      default_action = "redirect-https"
    }
    } : {
    http = {
      port           = 80
      protocol       = "HTTP"
      default_action = "fixed-response"
    }
  }

  listener_rules = {
    for k, s in var.services : k => {
      listener_key     = local.routing_listener
      priority         = local.svc[k].priority
      target_group_key = k
      host_headers     = s.host_headers
      path_patterns    = local.svc[k].path_patterns
    }
  }

  tags = var.tags
}

# =============================================================================
# Aurora PostgreSQL (optional, per service)
# =============================================================================

module "database" {
  # checkov:skip=CKV_AWS_133:backup_retention_period defaults to 7 days (services[*].database optional default); checkov cannot resolve for_each optional() values.
  # checkov:skip=CKV_AWS_139:deletion_protection defaults to true (services[*].database optional default); same for_each optional() resolution limit.
  # checkov:skip=CKV_AWS_327:kms_key_id is var.kms_key_arn, validated as a CMK ARN whenever services is non-empty; checkov only sees the empty default.
  source   = "../../data/rds-aurora"
  for_each = local.database_services

  name               = "${var.environment}-${each.key}"
  subnet_ids         = var.database_subnet_ids
  security_group_ids = [aws_security_group.database[each.key].id]
  port               = 5432

  engine_version             = each.value.database.engine_version
  instance_class             = each.value.database.instance_class
  instance_count             = each.value.database.instance_count
  enable_serverless_v2       = each.value.database.enable_serverless_v2
  serverless_v2_min_capacity = each.value.database.serverless_min_capacity
  serverless_v2_max_capacity = each.value.database.serverless_max_capacity
  database_name              = coalesce(each.value.database.database_name, replace(each.key, "-", "_"))

  # Master password generated + rotated by RDS in Secrets Manager (never in
  # Terraform state), encrypted with the workload CMK.
  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.kms_key_arn
  kms_key_id                    = var.kms_key_arn

  backup_retention_period = each.value.database.backup_retention_period
  deletion_protection     = each.value.database.deletion_protection
  skip_final_snapshot     = each.value.database.skip_final_snapshot

  tags = merge(var.tags, { Service = each.key })
}

# =============================================================================
# Fargate services
# =============================================================================

module "service" {
  source   = "../../compute/ecs-fargate"
  for_each = var.services

  name             = each.key
  region           = var.aws_region
  family           = local.svc[each.key].family
  cluster_arn      = aws_ecs_cluster.this[0].arn
  container_image  = coalesce(each.value.container_image, "${module.ecr[0].repository_urls[each.key]}:bootstrap")
  container_port   = each.value.container_port
  cpu              = each.value.cpu
  memory           = each.value.memory
  cpu_architecture = each.value.cpu_architecture
  desired_count    = each.value.desired_count

  container_environment = concat(
    [for n in sort(keys(each.value.environment)) : { name = n, value = each.value.environment[n] }],
    each.value.database != null ? [
      { name = "DB_HOST", value = module.database[each.key].endpoint },
      { name = "DB_PORT", value = "5432" },
      { name = "DB_NAME", value = module.database[each.key].database_name },
    ] : [],
  )

  # Secrets are ARN references resolved by the ECS agent at task start — never
  # plaintext in the task definition or Terraform state.
  container_secrets = concat(
    [for n in sort(keys(each.value.secrets)) : { name = n, valueFrom = each.value.secrets[n] }],
    each.value.database != null ? [
      { name = "DB_USERNAME", valueFrom = "${module.database[each.key].master_user_secret_arn}:username::" },
      { name = "DB_PASSWORD", valueFrom = "${module.database[each.key].master_user_secret_arn}:password::" },
    ] : [],
  )

  subnets            = var.service_subnet_ids
  security_group_ids = [aws_security_group.service[each.key].id]
  assign_public_ip   = false

  execution_role_arn = aws_iam_role.execution[each.key].arn
  task_role_arn      = aws_iam_role.task[each.key].arn

  target_group_arn = module.alb[0].target_group_arns[each.key]

  create_log_group = false
  log_group_name   = aws_cloudwatch_log_group.service[each.key].name

  # A service with a deploy role is rolled by CI: Terraform creates the first
  # revision, then stops reverting the revisions the pipeline registers.
  enable_external_deployments = contains(keys(local.deploy_services), each.key)
  enable_execute_command      = each.value.enable_execute_command

  enable_autoscaling       = each.value.enable_autoscaling
  autoscaling_min_capacity = each.value.autoscaling_min_capacity
  autoscaling_max_capacity = each.value.autoscaling_max_capacity

  tags = merge(var.tags, { Service = each.key })

  # The execution role must be able to pull + log before the first task starts.
  depends_on = [aws_iam_role_policy.execution]
}

# =============================================================================
# Alarms (optional)
# =============================================================================

module "alarms" {
  source = "../../ops/cloudwatch"
  count  = local.enabled && var.enable_alarms ? 1 : 0

  name_prefix   = local.cluster_name
  sns_topic_arn = var.alarm_sns_topic_arn

  alarms = merge([
    for k in local.service_keys : {
      "${k}-cpu-high" = {
        namespace           = "AWS/ECS"
        metric_name         = "CPUUtilization"
        comparison_operator = "GreaterThanOrEqualToThreshold"
        threshold           = 85
        evaluation_periods  = 3
        dimensions          = { ClusterName = local.cluster_name, ServiceName = k }
        alarm_description   = "${k}: average CPU >= 85% for 15 minutes."
      }
      "${k}-memory-high" = {
        namespace           = "AWS/ECS"
        metric_name         = "MemoryUtilization"
        comparison_operator = "GreaterThanOrEqualToThreshold"
        threshold           = 85
        evaluation_periods  = 3
        dimensions          = { ClusterName = local.cluster_name, ServiceName = k }
        alarm_description   = "${k}: average memory >= 85% for 15 minutes."
      }
      "${k}-unhealthy-targets" = {
        namespace           = "AWS/ApplicationELB"
        metric_name         = "UnHealthyHostCount"
        statistic           = "Maximum"
        comparison_operator = "GreaterThanThreshold"
        threshold           = 0
        period              = 60
        evaluation_periods  = 5
        dimensions = {
          LoadBalancer = module.alb[0].arn_suffix
          TargetGroup  = module.alb[0].target_group_arn_suffixes[k]
        }
        alarm_description = "${k}: at least one unhealthy ALB target for 5 minutes."
      }
      "${k}-target-5xx" = {
        namespace           = "AWS/ApplicationELB"
        metric_name         = "HTTPCode_Target_5XX_Count"
        statistic           = "Sum"
        comparison_operator = "GreaterThanThreshold"
        threshold           = 10
        dimensions = {
          LoadBalancer = module.alb[0].arn_suffix
          TargetGroup  = module.alb[0].target_group_arn_suffixes[k]
        }
        alarm_description = "${k}: more than 10 target 5xx responses in 5 minutes."
      }
    }
  ]...)

  tags = var.tags
}
