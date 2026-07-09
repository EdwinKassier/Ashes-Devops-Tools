# Phase-2 security root. Reads the phase-1 aws-organization root's remote state
# (credential-free config — the actual read happens with cloud creds at plan time)
# and composes the aws-security stage: the SRA security baseline across the
# management, security-tooling, log-archive and forensics accounts. It is a
# CONSUMER of the cross-root contract (organization_id, organization_root_id,
# account_ids, account_role_arns, management_account_id) and re-exports the
# security cross-root contract for downstream roots.
data "terraform_remote_state" "aws_organization" {
  backend = "cloud"
  config = {
    organization = var.tfc_organization
    workspaces   = { name = var.organization_workspace_name }
  }
}

module "aws_security" {
  source = "../../modules/stages/aws-security"

  # The default provider authenticates as / into the management account, so it is
  # mapped to both aws and aws.management. The other three are aliased providers
  # assuming cross-account roles from the organization remote state.
  providers = {
    aws                  = aws
    aws.management       = aws
    aws.security_tooling = aws.security_tooling
    aws.log_archive      = aws.log_archive
    aws.forensics        = aws.forensics
  }

  org_id                      = data.terraform_remote_state.aws_organization.outputs.organization_id
  org_root_id                 = data.terraform_remote_state.aws_organization.outputs.organization_root_id
  management_account_id       = data.terraform_remote_state.aws_organization.outputs.management_account_id
  security_tooling_account_id = data.terraform_remote_state.aws_organization.outputs.account_ids["security_tooling"]
  log_archive_account_id      = data.terraform_remote_state.aws_organization.outputs.account_ids["log_archive"]
  shared_services_account_id  = data.terraform_remote_state.aws_organization.outputs.account_ids["shared_services"]
  forensics_account_id        = data.terraform_remote_state.aws_organization.outputs.account_ids["forensics"]

  aws_region          = var.aws_region
  aws_enabled_regions = var.aws_enabled_regions

  log_archive_bucket_name     = var.log_archive_bucket_name
  key_admin_arn               = var.key_admin_arn
  config_role_arn             = var.config_role_arn
  aggregator_role_arn         = var.aggregator_role_arn
  meta_store_manager_role_arn = var.meta_store_manager_role_arn
  break_glass_role_arn        = var.break_glass_role_arn

  notification_subscribers  = var.notification_subscribers
  enabled_security_services = var.enabled_security_services
  enable_security_lake      = var.enable_security_lake
  enable_incident_response  = var.enable_incident_response
  enable_service_quotas     = var.enable_service_quotas
}
