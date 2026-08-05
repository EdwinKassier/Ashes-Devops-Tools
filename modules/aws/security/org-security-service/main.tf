# Map-gated org-security service enablement for the SRA landing zone.
#
# Macie, Inspector, Detective and Resource Explorer all share the same
# organization-enablement shape: register the delegated administrator from the
# MANAGEMENT account, then configure the service (and turn on auto-enable for
# new member accounts) from the delegated-administrator (Security Tooling)
# account. Terraform cannot dynamically switch resource TYPES, so instead of one
# parameterised resource this module contains a gated block per service and
# toggles each with `count = contains(var.enabled_services, "<name>") ? 1 : 0`.
# Adding a new org-security service = add a gated block here + a name to the
# allowed set in variables.tf.
#
# Two accounts / two providers:
#   * DEFAULT provider  -> the delegated-administrator account (Security Tooling).
#                          It owns the service accounts / graphs / indexes and
#                          the organization configurations.
#   * aws.management     -> the organization MANAGEMENT account. It owns only the
#                          delegated-admin registrations, which must be performed
#                          from the management account.

locals {
  macie_enabled             = contains(var.enabled_services, "macie") ? 1 : 0
  inspector_enabled         = contains(var.enabled_services, "inspector") ? 1 : 0
  detective_enabled         = contains(var.enabled_services, "detective") ? 1 : 0
  resource_explorer_enabled = contains(var.enabled_services, "resource-explorer") ? 1 : 0
}

# -----------------------------------------------------------------------------
# Macie
# -----------------------------------------------------------------------------

resource "aws_macie2_account" "this" {
  count = local.macie_enabled
}

# Registered from the MANAGEMENT account.
resource "aws_macie2_organization_admin_account" "this" {
  count            = local.macie_enabled
  provider         = aws.management
  admin_account_id = var.security_tooling_account_id
}

resource "aws_macie2_organization_configuration" "this" {
  count       = local.macie_enabled
  auto_enable = true

  depends_on = [aws_macie2_account.this, aws_macie2_organization_admin_account.this]
}

# -----------------------------------------------------------------------------
# Inspector
# -----------------------------------------------------------------------------

# Registered from the MANAGEMENT account.
resource "aws_inspector2_delegated_admin_account" "this" {
  count      = local.inspector_enabled
  provider   = aws.management
  account_id = var.security_tooling_account_id
}

resource "aws_inspector2_organization_configuration" "this" {
  count = local.inspector_enabled

  # auto_enable is a nested block (list, exactly one) in aws provider v6, not an
  # assignment. ec2 and ecr are required; lambda is optional.
  auto_enable {
    ec2    = true
    ecr    = true
    lambda = true
  }

  depends_on = [aws_inspector2_delegated_admin_account.this]
}

# Enable the standard Inspector scan types for the delegated-administrator
# account's own resources (org auto-enable only covers member accounts).
resource "aws_inspector2_enabler" "this" {
  count          = local.inspector_enabled
  account_ids    = [var.security_tooling_account_id]
  resource_types = ["EC2", "ECR", "LAMBDA"]

  depends_on = [aws_inspector2_delegated_admin_account.this]
}

# -----------------------------------------------------------------------------
# Detective (default OFF per SRA — not in the default enabled_services set)
# -----------------------------------------------------------------------------

resource "aws_detective_graph" "this" {
  count = local.detective_enabled
}

# Registered from the MANAGEMENT account.
resource "aws_detective_organization_admin_account" "this" {
  count      = local.detective_enabled
  provider   = aws.management
  account_id = var.security_tooling_account_id
}

resource "aws_detective_organization_configuration" "this" {
  count       = local.detective_enabled
  graph_arn   = aws_detective_graph.this[0].graph_arn
  auto_enable = true

  depends_on = [aws_detective_organization_admin_account.this]
}

# -----------------------------------------------------------------------------
# Resource Explorer
# -----------------------------------------------------------------------------
# The delegated-admin registration for resource-explorer-2 is handled by the
# aws/security-delegated-admin module, not here. This block only creates the
# aggregator index and default view in the Security Tooling account.

resource "aws_resourceexplorer2_index" "this" {
  count = local.resource_explorer_enabled
  type  = "AGGREGATOR"
}

resource "aws_resourceexplorer2_view" "this" {
  count = local.resource_explorer_enabled
  name  = "org-aggregator"

  depends_on = [aws_resourceexplorer2_index.this]
}
