# AWS Firewall Manager for the SRA landing zone.
#
# The organization MANAGEMENT account owns the FMS administrator registration,
# so aws_fms_admin_account uses the aliased `aws.management` provider. Once the
# Security Tooling account is the FMS admin, the FMS policies themselves are
# created there — the default provider — and enforced org-wide.

resource "aws_fms_admin_account" "this" {
  count    = var.enable_firewall_manager ? 1 : 0
  provider = aws.management

  account_id = var.fms_admin_account_id
}

resource "aws_fms_policy" "this" {
  for_each = var.enable_firewall_manager ? var.fms_policies : {}

  name                  = each.key
  exclude_resource_tags = false
  remediation_enabled   = try(each.value.remediation_enabled, true)
  resource_type         = each.value.resource_type

  security_service_policy_data {
    type                 = each.value.type # SECURITY_GROUPS_COMMON | WAFV2 | DNS_FIREWALL | NETWORK_FIREWALL
    managed_service_data = try(each.value.managed_service_data, null)
  }

  depends_on = [aws_fms_admin_account.this]
}
