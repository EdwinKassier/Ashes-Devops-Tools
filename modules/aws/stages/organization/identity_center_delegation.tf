# IAM Identity Center delegated administrator, registered by aws-organization
# (the phase-0 management role) rather than by aws-security: delegating
# sso.amazonaws.com is identity control over every account, so the
# least-privilege aws-security role is not allowed to do it.
resource "aws_organizations_delegated_administrator" "identity_center" {
  count = var.identity_center_admin_account_key == null ? 0 : 1

  account_id        = module.account[var.identity_center_admin_account_key].account_id
  service_principal = "sso.amazonaws.com"
}
