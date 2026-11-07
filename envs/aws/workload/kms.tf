# =============================================================================
# WORKLOAD CMK — created here unless var.kms_key_arn supplies one
#
# The workload needs a customer-managed key from its first apply: the Systems
# Manager baseline (Session Manager sessions/logs), the account default EBS key,
# and every app-services ECR repository, log group, Aurora cluster and RDS
# master secret. With kms_key_arn = "" (default) this root creates one per
# workload account, so the golden path needs no hand-made key.
#
# Key policy (no kms:ViaService on the log service — it would deny CloudWatch
# Logs; per-service-principal statements instead):
#   - the account root (IAM delegation: tfc-apply/plan roles, ECR, EBS, RDS and
#     Secrets Manager use the key through their caller's IAM permissions + grants),
#   - CloudWatch Logs in this region, scoped by the aws:logs:arn encryption
#     context to log groups in THIS account,
#   - ECR in this region on behalf of principals in this account,
#   - the app-services task execution roles (<environment>-<service>-exec) to
#     decrypt the secrets they inject: one exact ARN per declared service, built
#     from the service keys (not read from the roles, which would be a cycle:
#     the roles' policies need this key's ARN). They are matched by
#     aws:PrincipalArn on the account-root principal because KMS rejects a key
#     policy whose Principal names a role that does not exist yet, and the roles
#     are created after the key. No services = no statement (never an empty
#     principal list).
# =============================================================================

data "aws_partition" "current" {}

locals {
  create_kms_key = var.kms_key_arn == ""
  kms_partition  = data.aws_partition.current.partition

  # Exact ARNs of the task execution roles modules/aws/stages/app-services
  # creates (aws_iam_role.execution: "<environment>-<service>-exec").
  app_exec_role_arns = [
    for k in sort(keys(local.services)) : "arn:${local.kms_partition}:iam::${local.workload_account_id}:role/${local.environment}-${k}-exec"
  ]

  workload_kms_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid       = "AccountRootAdmin"
        Effect    = "Allow"
        Principal = { AWS = "arn:${local.kms_partition}:iam::${local.workload_account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "CloudWatchLogsThisAccount"
        Effect    = "Allow"
        Principal = { Service = "logs.${local.aws_region}.amazonaws.com" }
        Action = [
          "kms:Decrypt*",
          "kms:Describe*",
          "kms:Encrypt*",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*",
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:${local.kms_partition}:logs:${local.aws_region}:${local.workload_account_id}:log-group:*"
          }
        }
      },
      {
        # CloudWatch alarms publish to the app-services alarm topic, which is
        # encrypted with this key; without this grant notifications are
        # silently dropped.
        Sid       = "CloudWatchAlarmsToEncryptedTopic"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey*"]
        Resource  = "*"
        Condition = {
          StringEquals = { "aws:SourceAccount" = local.workload_account_id }
        }
      },
      {
        Sid       = "EcrThisAccount"
        Effect    = "Allow"
        Principal = { AWS = "arn:${local.kms_partition}:iam::${local.workload_account_id}:root" }
        Action = [
          "kms:CreateGrant",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = local.workload_account_id
            "kms:ViaService"    = "ecr.${local.aws_region}.amazonaws.com"
          }
        }
      },
      ], length(local.app_exec_role_arns) == 0 ? [] : [
      {
        Sid       = "AppTaskExecutionRolesDecrypt"
        Effect    = "Allow"
        Principal = { AWS = "arn:${local.kms_partition}:iam::${local.workload_account_id}:root" }
        Action    = ["kms:Decrypt", "kms:DescribeKey"]
        Resource  = "*"
        Condition = {
          ArnEquals = {
            "aws:PrincipalArn" = local.app_exec_role_arns
          }
        }
      },
    ])
  })

  # The key every consumer in this root uses.
  kms_key_arn = local.create_kms_key ? aws_kms_key.workload[0].arn : var.kms_key_arn
}

resource "aws_kms_key" "workload" {
  count = local.create_kms_key ? 1 : 0

  description             = "Workload CMK for aws-workload-${local.environment}: EBS default, Session Manager, app ECR repos, log groups, Aurora and RDS secrets."
  enable_key_rotation     = true
  rotation_period_in_days = 365
  deletion_window_in_days = 30
  policy                  = local.workload_kms_policy

  tags = { Name = "workload-${local.environment}" }
}

resource "aws_kms_alias" "workload" {
  count = local.create_kms_key ? 1 : 0

  name          = "alias/workload-${local.environment}"
  target_key_id = aws_kms_key.workload[0].key_id
}
