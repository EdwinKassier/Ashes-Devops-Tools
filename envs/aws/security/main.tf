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
  source = "../../../modules/aws/stages/security"

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
  identity_account_id         = var.identity_account_id
  forensics_account_id        = data.terraform_remote_state.aws_organization.outputs.account_ids["forensics"]

  aws_region          = var.aws_region
  aws_enabled_regions = var.aws_enabled_regions

  log_archive_bucket_name     = var.log_archive_bucket_name
  key_admin_arn               = var.key_admin_arn
  kms_key_user_arns           = var.kms_key_user_arns
  enable_kms_protection_tag   = var.enable_kms_protection_tag
  config_role_arn             = var.config_role_arn
  aggregator_role_arn         = var.aggregator_role_arn
  meta_store_manager_role_arn = var.meta_store_manager_role_arn
  break_glass_role_arn        = var.break_glass_role_arn

  # Managed break-glass role (audit M3): opt-in. When create_break_glass is true
  # the stage creates the role and watches it; otherwise break_glass_role_arn above
  # points at an externally-managed role.
  create_break_glass             = var.create_break_glass
  break_glass_role_name          = var.break_glass_role_name
  break_glass_trusted_principals = var.break_glass_trusted_principals
  break_glass_mfa_max_age        = var.break_glass_mfa_max_age
  break_glass_active             = var.break_glass_active

  notification_subscribers  = var.notification_subscribers
  enabled_security_services = var.enabled_security_services
  enable_security_lake      = var.enable_security_lake

  # FinOps F5: cost toggles for the two most expensive always-on security
  # services. Default true (full coverage); set false for non-prod.
  config_record_all_supported             = var.config_record_all_supported
  guardduty_enable_ebs_malware_protection = var.guardduty_enable_ebs_malware_protection
  enable_incident_response                = var.enable_incident_response
  enable_service_quotas                   = var.enable_service_quotas

  # CloudTrail: CIS section-4 alarms (default on, self-sufficient CMK + SNS)
  # and S3 object-level data events (CIS 3.8 write by default).
  enable_cloudwatch_logs                         = var.enable_cloudwatch_logs
  cloudwatch_logs_retention_days                 = var.cloudwatch_logs_retention_days
  cloudwatch_logs_kms_key_arn                    = var.cloudwatch_logs_kms_key_arn
  cloudtrail_alarm_sns_topic_arn                 = var.cloudtrail_alarm_sns_topic_arn
  cloudtrail_alarm_subscribers                   = var.cloudtrail_alarm_subscribers
  cloudtrail_cis_alarms_excluded                 = var.cloudtrail_cis_alarms_excluded
  cloudtrail_s3_data_events                      = var.cloudtrail_s3_data_events
  cloudtrail_s3_data_events_excluded_bucket_arns = var.cloudtrail_s3_data_events_excluded_bucket_arns
  cloudtrail_lambda_data_events                  = var.cloudtrail_lambda_data_events
}
