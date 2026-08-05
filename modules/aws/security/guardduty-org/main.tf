# Org-wide, multi-Region GuardDuty for the SRA landing zone.
#
# Two accounts / two providers:
#   * DEFAULT provider  -> the delegated-administrator account (Security Tooling).
#                          It owns the detector, org configuration and the
#                          protection-plan features in every enabled Region.
#   * aws.management     -> the organization MANAGEMENT account. It only owns the
#                          delegated-admin registration
#                          (aws_guardduty_organization_admin_account), which must
#                          be done from the management account.
#
# AWS provider v6 injects a per-resource `region`, so a SINGLE aws.management
# alias covers every Region via `region = each.value` — no per-Region provider
# aliases are required.
#
# Notes:
#   * Extended Threat Detection is enabled automatically once a detector exists;
#     there is no separate Terraform resource for it.
#   * S3 Malware Protection (malware-protection-plan) is managed out-of-band and
#     is intentionally not modelled here.
#   * The deprecated `datasources` block on aws_guardduty_detector /
#     aws_guardduty_organization_configuration is intentionally omitted; data
#     sources are configured through the feature resources instead.

resource "aws_guardduty_detector" "this" {
  for_each = toset(var.aws_enabled_regions)
  region   = each.value
  enable   = true
}

# Registered from the MANAGEMENT account: nominates the Security Tooling account
# as the GuardDuty delegated administrator in each enabled Region.
resource "aws_guardduty_organization_admin_account" "this" {
  provider         = aws.management
  for_each         = toset(var.aws_enabled_regions)
  region           = each.value
  admin_account_id = var.security_tooling_account_id
}

resource "aws_guardduty_organization_configuration" "this" {
  for_each                         = toset(var.aws_enabled_regions)
  region                           = each.value
  detector_id                      = aws_guardduty_detector.this[each.key].id
  auto_enable_organization_members = "ALL"

  # Registration must land before the org configuration is written.
  depends_on = [aws_guardduty_organization_admin_account.this]
}

locals {
  base_features = [
    "S3_DATA_EVENTS",
    "EKS_AUDIT_LOGS",
    "RDS_LOGIN_EVENTS",
    "LAMBDA_NETWORK_LOGS",
    "RUNTIME_MONITORING",
  ]

  # EBS malware protection carries a per-scan cost, so it is toggle-gated.
  features = var.enable_ebs_malware_protection ? concat(local.base_features, ["EBS_MALWARE_PROTECTION"]) : local.base_features

  # Fan the features out across every enabled Region: region x feature-name.
  region_feature = {
    for pair in setproduct(var.aws_enabled_regions, local.features) :
    "${pair[0]}:${pair[1]}" => { region = pair[0], feature = pair[1] }
  }
}

resource "aws_guardduty_organization_configuration_feature" "this" {
  for_each    = local.region_feature
  region      = each.value.region
  detector_id = aws_guardduty_detector.this[each.value.region].id
  name        = each.value.feature
  auto_enable = "ALL"
}
