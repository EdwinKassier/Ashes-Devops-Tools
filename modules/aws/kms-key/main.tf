# Reusable customer-managed KMS key (CMK) sized for cross-account log delivery.
#
# The key policy is assembled with jsonencode() in a locals block (not via
# data.aws_iam_policy_document) so the rendered JSON is real under
# `mock_provider "aws"` and its content can be asserted on in tests.
#
# Statement design:
#   * KeyAdministration — a kms:* grant to var.key_admin_arn. REQUIRED to avoid
#     locking the key: AWS treats a CMK with no admin as effectively
#     unmanageable. This grants PutKeyPolicy/GetKeyPolicy/etc. to a key admin in
#     the CMK's own account.
#   * Per-log-service grants — one Allow per entry in log_service_principals,
#     scoped by aws:SourceOrgID so only principals in this org can use the key.
#     CloudTrail additionally requires an EncryptionContext condition on the
#     trail ARN. These grants deliberately DO NOT use kms:ViaService: CloudTrail
#     (and Config/Security Lake) call KMS under their own service principal, not
#     via S3, so a ViaService condition would deny log delivery.
#   * Optional general-usage grant for var.key_users, optionally scoped by
#     var.via_services. This ViaService scoping applies only to generic
#     application usage, never to the log-service grants above.
#   * Optional service-principal grant for var.service_principals — one Allow for
#     the whole list, scoped by aws:SourceOrgID. This lets local AWS services in
#     the key's own account (e.g. SNS, SSM, CloudWatch) use the key to
#     encrypt/decrypt, without the CloudTrail EncryptionContext condition the
#     log-service grants carry. Distinct from log_service_principals so a
#     non-log-delivery key (e.g. a security-tooling CMK) can grant service usage
#     without pretending to be a log-delivery target.

locals {
  # Log-service grants. CloudTrail gets an extra EncryptionContext condition.
  log_service_statements = [
    for principal in var.log_service_principals : {
      Sid       = "Allow-${replace(principal, ".", "-")}"
      Effect    = "Allow"
      Principal = { Service = principal }
      Action = [
        "kms:GenerateDataKey*",
        "kms:Decrypt",
        "kms:DescribeKey",
      ]
      Resource = "*"
      Condition = principal == "cloudtrail.amazonaws.com" ? {
        StringEquals = { "aws:SourceOrgID" = var.org_id }
        StringLike   = { "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:aws:cloudtrail:*:${var.management_account_id}:trail/*" }
        } : {
        StringEquals = { "aws:SourceOrgID" = var.org_id }
      }
    }
  ]

  # Optional general-usage grant for application principals. Scoped by
  # via_services when that list is non-empty.
  key_user_statements = length(var.key_users) > 0 ? [
    merge(
      {
        Sid       = "KeyUsage"
        Effect    = "Allow"
        Principal = { AWS = var.key_users }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
        ]
        Resource = "*"
      },
      length(var.via_services) > 0 ? {
        Condition = { StringEquals = { "kms:ViaService" = var.via_services } }
      } : {},
    )
  ] : []

  # Optional grant for local AWS service principals (SNS/SSM/CloudWatch/...) that
  # need to use the key in its own account. Scoped by aws:SourceOrgID so only
  # calls originating within this org can use it. One statement for the whole
  # list; no CloudTrail EncryptionContext condition.
  service_principal_statements = length(var.service_principals) > 0 ? [
    {
      Sid       = "ServiceUsage"
      Effect    = "Allow"
      Principal = { Service = var.service_principals }
      Action = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
      ]
      Resource  = "*"
      Condition = { StringEquals = { "aws:SourceOrgID" = var.org_id } }
    }
  ] : []

  key_admin_statement = {
    Sid       = "KeyAdministration"
    Effect    = "Allow"
    Principal = { AWS = var.key_admin_arn }
    Action    = ["kms:*"]
    Resource  = "*"
  }

  key_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [local.key_admin_statement],
      local.log_service_statements,
      local.key_user_statements,
      local.service_principal_statements,
    )
  })
}

resource "aws_kms_key" "this" {
  description             = "CMK: ${var.alias}"
  enable_key_rotation     = true
  deletion_window_in_days = var.deletion_window_in_days
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.alias}"
  target_key_id = aws_kms_key.this.key_id
}

resource "aws_kms_key_policy" "this" {
  key_id = aws_kms_key.this.key_id
  policy = local.key_policy
}
