# AWS IAM Identity Center (successor to AWS SSO) permission sets, account
# assignments, and optional ABAC configuration WITHIN an already-existing
# Identity Center instance.
#
# The Identity Center INSTANCE itself is enabled out-of-band: it cannot be
# created by Terraform (there is no manageable resource for the instance), so it
# must be turned on once in the organization management account via the console
# or `aws sso-admin`/Organizations API before this module runs. This module
# therefore DISCOVERS the instance with a data source and manages only the
# permission sets and assignments inside it.

data "aws_ssoadmin_instances" "this" {}

locals {
  # An organization has exactly one Identity Center instance; take the first
  # (and only) entry of each parallel list the data source returns.
  instance_arn      = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]

  # Flatten permission_sets x their managed_policy_arns into a single map whose
  # keys are plan-known strings ("<permission set>/<policy arn>"), so each
  # attachment is an independent, statically-keyed for_each element.
  managed_attachments = merge([
    for ps_name, ps in var.permission_sets : {
      for arn in ps.managed_policy_arns :
      "${ps_name}/${arn}" => { ps = ps_name, arn = arn }
    }
  ]...)
}

resource "aws_ssoadmin_permission_set" "this" {
  for_each = var.permission_sets

  instance_arn     = local.instance_arn
  name             = each.key
  description      = each.value.description
  session_duration = each.value.session_duration # ISO-8601 duration, e.g. "PT1H"
}

resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each = local.managed_attachments

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.ps].arn
  managed_policy_arn = each.value.arn
}

resource "aws_ssoadmin_permission_set_inline_policy" "this" {
  for_each = { for k, v in var.permission_sets : k => v if try(v.inline_policy, "") != "" }

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.key].arn
  inline_policy      = each.value.inline_policy
}

resource "aws_ssoadmin_account_assignment" "this" {
  for_each = var.assignments

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set].arn
  principal_type     = each.value.principal_type # GROUP | USER
  principal_id       = each.value.principal_id
  target_id          = each.value.account_id
  target_type        = "AWS_ACCOUNT"
}

# Attribute-based access control (ABAC): enables passing IdP/session attributes
# through to permission-set policy conditions (aws:PrincipalTag/<key>).
resource "aws_ssoadmin_instance_access_control_attributes" "this" {
  count = var.enable_abac ? 1 : 0

  instance_arn = local.instance_arn

  dynamic "attribute" {
    for_each = var.abac_attributes
    content {
      key = attribute.key
      value {
        source = attribute.value
      }
    }
  }
}
