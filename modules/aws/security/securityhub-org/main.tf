# Org-wide Security Hub with CENTRAL configuration for the SRA landing zone.
#
# Two accounts / two providers:
#   * DEFAULT provider  -> the delegated-administrator account (Security Tooling).
#                          It owns the Security Hub account enablement, the finding
#                          aggregator, the organization configuration and the
#                          configuration policy + its root association.
#   * aws.management     -> the organization MANAGEMENT account. It only owns the
#                          delegated-admin registration
#                          (aws_securityhub_organization_admin_account), which must
#                          be performed from the management account.
#
# CENTRAL configuration prerequisites (enforced here via depends_on ordering):
#   1. Security Hub must be enabled in the delegated-admin account.
#   2. The delegated admin must be registered (from the management account).
#   3. A finding aggregator must already exist BEFORE the organization
#      configuration is switched to CENTRAL.
#   4. The organization configuration must set auto_enable = false and
#      auto_enable_standards = "NONE" (both required for CENTRAL).
#
# The delegated admin MUST be a MEMBER account (Security Tooling), NOT the
# management account. This is the mature CSPM path; Security Hub V2 (unified
# security posture) is a future migration and is intentionally not modelled here.

locals {
  # A variable default cannot reference another variable, so the FSBP + CIS 1.4 +
  # NIST 800-53 r5 standard ARN set is computed here from home_region and used
  # only when the caller does not supply an explicit enabled_standard_arns list.
  # CIS 1.4 is a region-agnostic ruleset ARN (no region segment); FSBP and NIST
  # are region-scoped standards ARNs.
  default_standards = [
    "arn:aws:securityhub:${var.home_region}::standards/aws-foundational-security-best-practices/v/1.0.0",
    "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.4.0",
    "arn:aws:securityhub:${var.home_region}::standards/nist-800-53/v/5.0.0",
  ]

  enabled_standard_arns = length(var.enabled_standard_arns) > 0 ? var.enabled_standard_arns : local.default_standards
}

# Enables Security Hub in the delegated-administrator (Security Tooling) account.
resource "aws_securityhub_account" "this" {}

# Registered from the MANAGEMENT account: nominates the Security Tooling account
# as the Security Hub delegated administrator for the organization.
resource "aws_securityhub_organization_admin_account" "this" {
  provider         = aws.management
  admin_account_id = var.security_tooling_account_id

  depends_on = [aws_securityhub_account.this]
}

# Finding aggregator is a PREREQUISITE for CENTRAL configuration. ALL_REGIONS
# aggregates findings from every current and future Region into the home Region.
resource "aws_securityhub_finding_aggregator" "this" {
  linking_mode = "ALL_REGIONS"

  depends_on = [aws_securityhub_organization_admin_account.this]
}

# Switches the organization to CENTRAL configuration. auto_enable = false and
# auto_enable_standards = "NONE" are both REQUIRED for CENTRAL; enablement is
# instead driven by the configuration policy below.
resource "aws_securityhub_organization_configuration" "this" {
  auto_enable           = false
  auto_enable_standards = "NONE"

  organization_configuration {
    configuration_type = "CENTRAL"
  }

  depends_on = [aws_securityhub_finding_aggregator.this]
}

# Baseline configuration policy: enables Security Hub with the FSBP + CIS + NIST
# standards and (optionally) disables specific control identifiers org-wide.
resource "aws_securityhub_configuration_policy" "baseline" {
  name = var.policy_name

  configuration_policy {
    service_enabled       = true
    enabled_standard_arns = local.enabled_standard_arns

    security_controls_configuration {
      disabled_control_identifiers = var.disabled_control_identifiers
    }
  }

  depends_on = [aws_securityhub_organization_configuration.this]
}

# Associates the baseline policy to the organization root so it applies to every
# OU and account (including future accounts) unless overridden lower in the tree.
resource "aws_securityhub_configuration_policy_association" "root" {
  target_id = var.org_root_id
  policy_id = aws_securityhub_configuration_policy.baseline.id
}
