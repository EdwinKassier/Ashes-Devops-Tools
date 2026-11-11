# Reusable customer-managed KMS key (CMK) sized for cross-account log delivery.
#
# The key policy is assembled with jsonencode() in a locals block (not via
# data.aws_iam_policy_document) so the rendered JSON is real under
# `mock_provider "aws"` and its content can be asserted on in tests.
#
# Statement design:
#   * KeyAdministration — management-plane actions ONLY for var.key_admin_arn
#     (Enable/Disable, rotation, tagging, deletion scheduling...), NOT
#     PutKeyPolicy (see KeyPolicyAdministration).
#   * KeyPolicyAdministration — kms:PutKeyPolicy only, for
#     var.key_policy_admin_arns (break-glass); falls back to key_admin_arn.
#     REQUIRED to avoid locking the key. It deliberately grants NO cryptographic
#     operations (Encrypt/Decrypt/ReEncrypt/GenerateDataKey) and NO
#     kms:CreateGrant, so the key administrator cannot read data protected by
#     the key nor grant itself usage — separation of key administration from key
#     usage (AWS KMS best practice). Destruction of protected keys is further
#     gated by the deny-tamper SCP (protection tag, break-glass only).
#   * Per-log-service grants — one Allow per entry in log_service_principals,
#     scoped by aws:SourceOrgID so only principals in this org can use the key.
#     CloudTrail additionally requires an EncryptionContext condition on the
#     trail ARN. These grants deliberately DO NOT use kms:ViaService: CloudTrail
#     (and Config/Security Lake) call KMS under their own service principal, not
#     via S3, so a ViaService condition would deny log delivery.
#   * Optional general-usage grant for var.key_user_arns, optionally scoped by
#     var.via_services. This ViaService scoping applies only to generic
#     application usage, never to the log-service grants above.
#   * Optional service-principal grant for var.service_principals — one Allow for
#     the whole list, scoped by default to the key's OWN account
#     (aws:SourceAccount = key_account_id), so a service acting for another org
#     account cannot use the key. service_principal_scope = "organization"
#     widens it to aws:SourceOrgID (opt-in, for keys that genuinely take
#     org-wide service writes). This lets local AWS services in the key's own
#     account (e.g. SNS, SSM, CloudWatch) use the key to encrypt/decrypt,
#     without the CloudTrail EncryptionContext condition the log-service
#     grants carry. (The log-service grants above stay org-wide by design:
#     CloudTrail/Config ORGANIZATION delivery writes on behalf of every
#     member account.) Distinct from log_service_principals so a
#     non-log-delivery key (e.g. a security-tooling CMK) can grant service usage
#     without pretending to be a log-delivery target.

# The key's own account, for the account-scoped ServiceUsage condition. Read
# only when needed and not supplied.
data "aws_caller_identity" "current" {
  count = var.key_account_id == null && length(var.service_principals) > 0 && var.service_principal_scope == "account" ? 1 : 0
}

locals {
  key_account_id = coalesce(var.key_account_id, try(data.aws_caller_identity.current[0].account_id, null), "unused")

  # Log-service grants. CloudTrail gets an extra EncryptionContext condition.
  #
  # ⚠️ AUDIT A1 (unvalidated, real-apply): AWS documents aws:SourceArn (the trail
  # ARN) — not aws:SourceOrgID — as the CloudTrail KMS-key-policy condition
  # (SourceOrgID is documented for the S3 bucket policy). If CloudTrail does not
  # emit SourceOrgID on its KMS GenerateDataKey*/Decrypt calls, the StringEquals
  # below fails closed and log delivery breaks. This has only been mock_provider-
  # tested. Before relying on it in a real org, switch the CloudTrail branch to
  # aws:SourceArn = arn:aws:cloudtrail:<region>:${var.management_account_id}:trail/<name>
  # (or StringLike on the account-scoped pattern) and confirm Config/Security Lake
  # actually emit SourceOrgID to KMS. See CLAUDE.md gotcha #5.
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
        StringLike   = { "kms:EncryptionContext:aws:cloudtrail:arn" = "arn:${local.partition}:cloudtrail:*:${var.management_account_id}:trail/*" }
        } : {
        StringEquals = { "aws:SourceOrgID" = var.org_id }
      }
    }
  ]

  # Optional general-usage grant for application principals. Scoped by
  # via_services when that list is non-empty.
  key_user_statements = length(var.key_user_arns) > 0 ? [
    merge(
      {
        Sid       = "KeyUsage"
        Effect    = "Allow"
        Principal = { AWS = var.key_user_arns }
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
  # need to use the key in its own account. Scoped to the key's own account
  # (aws:SourceAccount) by default, or the whole org (aws:SourceOrgID) when
  # service_principal_scope = "organization". One statement for the whole list;
  # no CloudTrail EncryptionContext condition.
  service_principal_condition = var.service_principal_scope == "organization" ? {
    StringEquals = { "aws:SourceOrgID" = var.org_id }
    } : {
    StringEquals = { "aws:SourceAccount" = local.key_account_id }
  }

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
      Condition = local.service_principal_condition
    }
  ] : []

  # Management-plane actions only. kms:Create* is narrowed to CreateAlias so the
  # admin cannot CreateGrant itself cryptographic usage.
  key_admin_actions = [
    "kms:CreateAlias",
    "kms:Describe*",
    "kms:Enable*",
    "kms:List*",
    "kms:Update*",
    "kms:Revoke*",
    "kms:Disable*",
    "kms:Get*",
    "kms:Delete*",
    "kms:TagResource",
    "kms:UntagResource",
    "kms:ScheduleKeyDeletion",
    "kms:CancelKeyDeletion",
    "kms:RotateKeyOnDemand",
  ]

  key_admin_statement = {
    Sid       = "KeyAdministration"
    Effect    = "Allow"
    Principal = { AWS = var.key_admin_arn }
    Action    = local.key_admin_actions
    Resource  = "*"
  }

  # kms:PutKeyPolicy is split out of KeyAdministration: whoever can rewrite the
  # key policy can grant itself kms:Decrypt, so it goes only to
  # key_policy_admin_arns (break-glass). Empty falls back to key_admin_arn
  # (legacy behaviour). On keys carrying the protection tag the deny-tamper SCP
  # additionally restricts PutKeyPolicy to break-glass in member accounts.
  key_policy_admin_principals = length(var.key_policy_admin_arns) > 0 ? var.key_policy_admin_arns : [var.key_admin_arn]

  key_policy_admin_statement = {
    Sid       = "KeyPolicyAdministration"
    Effect    = "Allow"
    Principal = { AWS = local.key_policy_admin_principals }
    Action    = ["kms:PutKeyPolicy"]
    Resource  = "*"
  }

  key_tags = merge(
    var.tags,
    var.enable_protection_tag ? { (var.protection_tag_key) = "true" } : {},
  )

  key_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [local.key_admin_statement, local.key_policy_admin_statement],
      local.log_service_statements,
      local.key_user_statements,
      local.service_principal_statements,
    )
  })
}

# The key policy is set AT CreateKey (aws_kms_key.policy), not by a separate
# aws_kms_key_policy PutKeyPolicy call: the deny-tamper SCP lets only
# break-glass PutKeyPolicy on protected keys, so a post-create PutKeyPolicy by
# the pipeline would be denied. Consequence: any LATER Terraform change to a
# protected key's policy must be applied by break-glass.
#
# When key_policy_admin_arns is set, the caller (pipeline) is deliberately not
# granted PutKeyPolicy, so KMS's lockout safety check is bypassed — the
# key_policy_admin_arns principals retain PutKeyPolicy, so the key is never
# unmanageable.
resource "aws_kms_key" "this" {
  description                        = "CMK: ${var.alias}"
  enable_key_rotation                = true
  deletion_window_in_days            = var.deletion_window_in_days
  policy                             = local.key_policy
  bypass_policy_lockout_safety_check = length(var.key_policy_admin_arns) > 0
  tags                               = local.key_tags
}

# Formerly a separate aws_kms_key_policy. Forget it without destroying (a
# destroy would reset the key to the default policy); aws_kms_key.policy now
# owns the same document.
removed {
  from = aws_kms_key_policy.this

  lifecycle {
    destroy = false
  }
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.alias}"
  target_key_id = aws_kms_key.this.key_id
}

# ---------------------------------------------------------------------------
# Deletion guard
#
# prevent_destroy must be a static literal, so a terraform_data guard carries
# it. replace_triggered_by ties the guard to the key: a plan that destroys OR
# replaces the key (which schedules the old key, and everything encrypted
# under it, for deletion) must also replace the guard, which prevent_destroy
# refuses. Setting enable_deletion_protection = false does not lift an existing
# guard (removing it is itself a destroy). To retire the key deliberately,
# first run:
#   terraform state rm '<module_address>.terraform_data.deletion_guard[0]'
# ---------------------------------------------------------------------------

resource "terraform_data" "deletion_guard" {
  count = var.enable_deletion_protection ? 1 : 0

  input = "alias/${var.alias}"

  lifecycle {
    prevent_destroy      = true
    replace_triggered_by = [aws_kms_key.this.id]
  }
}
