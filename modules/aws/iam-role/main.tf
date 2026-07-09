# Cross-account / workload / break-glass IAM roles for the SRA landing zone.
#
# `roles` is a generic map of IAM roles keyed by name: each carries its own
# trust policy (JSON string), optional session duration, managed policy ARNs,
# an optional inline policy, and an optional permissions boundary. This is the
# workhorse for cross-account access and workload execution roles.
#
# The break-glass role is a separate, single, opinionated role: it is disabled
# by default (a deny-all standing policy) and requires recent MFA to assume.
# During an incident it is activated by flipping `break_glass_active`, which
# swaps the deny-all standing policy for the AWS-managed AdministratorAccess.
# There is deliberately no CloudWatch alarm here; the break-glass-use alarm
# lives in the security-notifications module (C14).

locals {
  # Flatten roles x managed_policy_arns into plan-known attachment keys.
  # Keying on "role|arn" keeps keys stable and known at plan time.
  role_managed_attachments = merge([
    for role_name, role in var.roles : {
      for arn in role.managed_policy_arns :
      "${role_name}|${arn}" => {
        role = role_name
        arn  = arn
      }
    }
  ]...)
}

resource "aws_iam_role" "this" {
  # checkov:skip=CKV_AWS_61:Trust policy is caller-supplied (var.roles[*].trust_policy);
  # cross-account roles legitimately allow sts:AssumeRole from another account's
  # principal. Scoping of the trust relationship is the caller's responsibility.
  for_each             = var.roles
  name                 = each.key
  assume_role_policy   = each.value.trust_policy
  max_session_duration = try(each.value.max_session_duration, 3600)
  permissions_boundary = try(each.value.permissions_boundary, null)
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each   = local.role_managed_attachments
  role       = aws_iam_role.this[each.value.role].name
  policy_arn = each.value.arn
}

resource "aws_iam_role_policy" "inline" {
  for_each = { for k, v in var.roles : k => v if try(v.inline_policy, "") != "" }
  name     = "${each.key}-inline"
  role     = aws_iam_role.this[each.key].id
  policy   = each.value.inline_policy
}

# -----------------------------------------------------------------------------
# Break-glass role: MFA-required trust + disabled-by-default standing policy.
# -----------------------------------------------------------------------------

resource "aws_iam_role" "break_glass" {
  count                = var.enable_break_glass ? 1 : 0
  name                 = var.break_glass_role_name
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = var.break_glass_trusted_principals } # account-qualified ARNs
      Action    = "sts:AssumeRole"
      Condition = {
        Bool            = { "aws:MultiFactorAuthPresent" = "true" }
        NumericLessThan = { "aws:MultiFactorAuthAge" = tostring(var.break_glass_mfa_max_age) }
      }
    }]
  })
}

# Standing state: deny-all unless explicitly activated during an incident.
resource "aws_iam_role_policy" "break_glass_standing" {
  count = var.enable_break_glass && !var.break_glass_active ? 1 : 0
  name  = "break-glass-deny-all"
  role  = aws_iam_role.break_glass[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Deny"
      Action   = "*"
      Resource = "*"
    }]
  })
}

# Active state: attach AdministratorAccess only while an incident is declared.
resource "aws_iam_role_policy_attachment" "break_glass_active" {
  # checkov:skip=CKV_AWS_274:AdministratorAccess is the intended break-glass
  # grant, attached ONLY when break_glass_active=true during a declared
  # incident. The standing state is deny-all (see break_glass_standing).
  count      = var.enable_break_glass && var.break_glass_active ? 1 : 0
  role       = aws_iam_role.break_glass[0].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
