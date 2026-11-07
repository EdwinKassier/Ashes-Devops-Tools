# tflint-ignore-file: terraform_typed_variables, terraform_standard_module_structure
# (untyped on purpose so any old value type still reaches the guard; kept apart
# from variables.tf so the whole file goes at v1.0)

# Removed inputs (v0.2.0): every tuning input of this root moved into the
# gcp_overrides object (UPGRADING.md, "Object pass-through"). The old names are
# declared again, untyped and inert, only so that a value still set in a tfvars
# file, a TFC workspace variable or a TF_VAR_ environment variable fails the
# plan instead of being ignored; `deprecated` also names the replacement in a
# warning on the same run. Removed at v1.0.

variable "admin_email" {
  description = "REMOVED in v0.2.0: use gcp_overrides.admin_email."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.admin_email instead. This declaration goes at v1.0."
  default     = null
}

variable "break_glass_user" {
  description = "REMOVED in v0.2.0: use gcp_overrides.break_glass_user."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.break_glass_user instead. This declaration goes at v1.0."
  default     = null
}

variable "organization_admin_groups" {
  description = "REMOVED in v0.2.0: use gcp_overrides.organization_admin_groups."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.organization_admin_groups instead. This declaration goes at v1.0."
  default     = null
}

variable "billing_admin_groups" {
  description = "REMOVED in v0.2.0: use gcp_overrides.billing_admin_groups."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.billing_admin_groups instead. This declaration goes at v1.0."
  default     = null
}

variable "allowed_regions" {
  description = "REMOVED in v0.2.0: use gcp_overrides.allowed_regions."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.allowed_regions instead. This declaration goes at v1.0."
  default     = null
}

variable "strict_folder_policy_environment_keys" {
  description = "REMOVED in v0.2.0: use gcp_overrides.strict_folder_policy_environment_keys."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.strict_folder_policy_environment_keys instead. This declaration goes at v1.0."
  default     = null
}

variable "security_contact_email" {
  description = "REMOVED in v0.2.0: use gcp_overrides.security_contact_email."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.security_contact_email instead. This declaration goes at v1.0."
  default     = null
}

variable "billing_contact_email" {
  description = "REMOVED in v0.2.0: use gcp_overrides.billing_contact_email."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.billing_contact_email instead. This declaration goes at v1.0."
  default     = null
}

variable "budget_currency" {
  description = "REMOVED in v0.2.0: use gcp_overrides.budget_currency."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.budget_currency instead. This declaration goes at v1.0."
  default     = null
}

variable "custom_org_constraints" {
  description = "REMOVED in v0.2.0: use gcp_overrides.custom_org_constraints."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.custom_org_constraints instead. This declaration goes at v1.0."
  default     = null
}

variable "enable_audit_bucket_lock" {
  description = "REMOVED in v0.2.0: use gcp_overrides.enable_audit_bucket_lock."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.enable_audit_bucket_lock instead. This declaration goes at v1.0."
  default     = null
}

variable "iam_deny_policies" {
  description = "REMOVED in v0.2.0: use gcp_overrides.iam_deny_policies."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.iam_deny_policies instead. This declaration goes at v1.0."
  default     = null
}

variable "logging_project_id" {
  description = "REMOVED in v0.2.0: use gcp_overrides.logging_project_id."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.logging_project_id instead. This declaration goes at v1.0."
  default     = null
}

variable "logging_project_number" {
  description = "REMOVED in v0.2.0: use gcp_overrides.logging_project_number."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.logging_project_number instead. This declaration goes at v1.0."
  default     = null
}

variable "audit_soft_delete_retention_days" {
  description = "REMOVED in v0.2.0: use gcp_overrides.audit_soft_delete_retention_days."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.audit_soft_delete_retention_days instead. This declaration goes at v1.0."
  default     = null
}

variable "enforce_os_login" {
  description = "REMOVED in v0.2.0: use gcp_overrides.enforce_os_login."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.enforce_os_login instead. This declaration goes at v1.0."
  default     = null
}

variable "os_login_exempt_environment_keys" {
  description = "REMOVED in v0.2.0: use gcp_overrides.os_login_exempt_environment_keys."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.os_login_exempt_environment_keys instead. This declaration goes at v1.0."
  default     = null
}

variable "enable_cis_log_metrics" {
  description = "REMOVED in v0.2.0: use gcp_overrides.enable_cis_log_metrics."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.enable_cis_log_metrics instead. This declaration goes at v1.0."
  default     = null
}

variable "enable_control_plane_alerting" {
  description = "REMOVED in v0.2.0: use gcp_overrides.enable_control_plane_alerting."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.enable_control_plane_alerting instead. This declaration goes at v1.0."
  default     = null
}

variable "alert_notification_emails" {
  description = "REMOVED in v0.2.0: use gcp_overrides.alert_notification_emails."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.alert_notification_emails instead. This declaration goes at v1.0."
  default     = null
}

variable "alert_notification_channels" {
  description = "REMOVED in v0.2.0: use gcp_overrides.alert_notification_channels."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.alert_notification_channels instead. This declaration goes at v1.0."
  default     = null
}

variable "break_glass_principal_emails" {
  description = "REMOVED in v0.2.0: use gcp_overrides.break_glass_principal_emails."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.break_glass_principal_emails instead. This declaration goes at v1.0."
  default     = null
}

variable "enable_cmek_org_policy" {
  description = "REMOVED in v0.2.0: use gcp_overrides.enable_cmek_org_policy."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.enable_cmek_org_policy instead. This declaration goes at v1.0."
  default     = null
}

variable "cmek_required_services" {
  description = "REMOVED in v0.2.0: use gcp_overrides.cmek_required_services."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.cmek_required_services instead. This declaration goes at v1.0."
  default     = null
}

variable "enable_admin_containment" {
  description = "REMOVED in v0.2.0: use gcp_overrides.enable_admin_containment."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.enable_admin_containment instead. This declaration goes at v1.0."
  default     = null
}

variable "containment_exempt_principals" {
  description = "REMOVED in v0.2.0: use gcp_overrides.containment_exempt_principals."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.containment_exempt_principals instead. This declaration goes at v1.0."
  default     = null
}

variable "enable_legacy_admin_folder_roles" {
  description = "REMOVED in v0.2.0: use gcp_overrides.enable_legacy_admin_folder_roles."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.enable_legacy_admin_folder_roles instead. This declaration goes at v1.0."
  default     = null
}

variable "allow_user_principals_for_break_glass" {
  description = "REMOVED in v0.2.0: use gcp_overrides.allow_user_principals_for_break_glass."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.allow_user_principals_for_break_glass instead. This declaration goes at v1.0."
  default     = null
}

variable "enable_pam" {
  description = "REMOVED in v0.2.0: use gcp_overrides.enable_pam."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.enable_pam instead. This declaration goes at v1.0."
  default     = null
}

variable "pam_eligible_groups" {
  description = "REMOVED in v0.2.0: use gcp_overrides.pam_eligible_groups."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.pam_eligible_groups instead. This declaration goes at v1.0."
  default     = null
}

variable "pam_approver_groups" {
  description = "REMOVED in v0.2.0: use gcp_overrides.pam_approver_groups."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.pam_approver_groups instead. This declaration goes at v1.0."
  default     = null
}

variable "pam_max_request_duration" {
  description = "REMOVED in v0.2.0: use gcp_overrides.pam_max_request_duration."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.pam_max_request_duration instead. This declaration goes at v1.0."
  default     = null
}

variable "enable_scoped_access_policies" {
  description = "REMOVED in v0.2.0: use gcp_overrides.enable_scoped_access_policies."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.enable_scoped_access_policies instead. This declaration goes at v1.0."
  default     = null
}

variable "guardrail_owner_mode" {
  description = "REMOVED in v0.2.0: use gcp_overrides.guardrail_owner_mode."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.guardrail_owner_mode instead. This declaration goes at v1.0."
  default     = null
}

variable "prefer_managed_constraints" {
  description = "REMOVED in v0.2.0: use gcp_overrides.prefer_managed_constraints."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.prefer_managed_constraints instead. This declaration goes at v1.0."
  default     = null
}

variable "enable_log_analytics" {
  description = "REMOVED in v0.2.0: use gcp_overrides.enable_log_analytics."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.enable_log_analytics instead. This declaration goes at v1.0."
  default     = null
}

variable "log_analytics_retention_days" {
  description = "REMOVED in v0.2.0: use gcp_overrides.log_analytics_retention_days."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.log_analytics_retention_days instead. This declaration goes at v1.0."
  default     = null
}

variable "enable_logging_organization_settings" {
  description = "REMOVED in v0.2.0: use gcp_overrides.enable_logging_organization_settings."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.enable_logging_organization_settings instead. This declaration goes at v1.0."
  default     = null
}

variable "logging_settings_kms_key_name" {
  description = "REMOVED in v0.2.0: use gcp_overrides.logging_settings_kms_key_name."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.logging_settings_kms_key_name instead. This declaration goes at v1.0."
  default     = null
}

variable "enable_principal_access_boundary" {
  description = "REMOVED in v0.2.0: use gcp_overrides.enable_principal_access_boundary."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.enable_principal_access_boundary instead. This declaration goes at v1.0."
  default     = null
}

variable "principal_access_boundary_allowed_resources" {
  description = "REMOVED in v0.2.0: use gcp_overrides.principal_access_boundary_allowed_resources."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.principal_access_boundary_allowed_resources instead. This declaration goes at v1.0."
  default     = null
}

variable "restrict_cloud_run_ingress" {
  description = "REMOVED in v0.2.0: use gcp_overrides.restrict_cloud_run_ingress."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.restrict_cloud_run_ingress instead. This declaration goes at v1.0."
  default     = null
}

variable "org_policy_overrides" {
  description = "REMOVED in v0.2.0: use gcp_overrides.org_policy_overrides."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.org_policy_overrides instead. This declaration goes at v1.0."
  default     = null
}

variable "allowed_workload_identity_issuers" {
  description = "REMOVED in v0.2.0: use gcp_overrides.allowed_workload_identity_issuers."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.allowed_workload_identity_issuers instead. This declaration goes at v1.0."
  default     = null
}

variable "allowed_workload_identity_aws_accounts" {
  description = "REMOVED in v0.2.0: use gcp_overrides.allowed_workload_identity_aws_accounts."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.allowed_workload_identity_aws_accounts instead. This declaration goes at v1.0."
  default     = null
}

variable "wif_tenant_pin_enforcement" {
  description = "REMOVED in v0.2.0: use gcp_overrides.wif_tenant_pin_enforcement."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set gcp_overrides.wif_tenant_pin_enforcement instead. This declaration goes at v1.0."
  default     = null
}

locals {
  # Removed variable name => its value (null unless still set).
  removed_inputs = {
    admin_email                                 = var.admin_email
    break_glass_user                            = var.break_glass_user
    organization_admin_groups                   = var.organization_admin_groups
    billing_admin_groups                        = var.billing_admin_groups
    allowed_regions                             = var.allowed_regions
    strict_folder_policy_environment_keys       = var.strict_folder_policy_environment_keys
    security_contact_email                      = var.security_contact_email
    billing_contact_email                       = var.billing_contact_email
    budget_currency                             = var.budget_currency
    custom_org_constraints                      = var.custom_org_constraints
    enable_audit_bucket_lock                    = var.enable_audit_bucket_lock
    iam_deny_policies                           = var.iam_deny_policies
    logging_project_id                          = var.logging_project_id
    logging_project_number                      = var.logging_project_number
    audit_soft_delete_retention_days            = var.audit_soft_delete_retention_days
    enforce_os_login                            = var.enforce_os_login
    os_login_exempt_environment_keys            = var.os_login_exempt_environment_keys
    enable_cis_log_metrics                      = var.enable_cis_log_metrics
    enable_control_plane_alerting               = var.enable_control_plane_alerting
    alert_notification_emails                   = var.alert_notification_emails
    alert_notification_channels                 = var.alert_notification_channels
    break_glass_principal_emails                = var.break_glass_principal_emails
    enable_cmek_org_policy                      = var.enable_cmek_org_policy
    cmek_required_services                      = var.cmek_required_services
    enable_admin_containment                    = var.enable_admin_containment
    containment_exempt_principals               = var.containment_exempt_principals
    enable_legacy_admin_folder_roles            = var.enable_legacy_admin_folder_roles
    allow_user_principals_for_break_glass       = var.allow_user_principals_for_break_glass
    enable_pam                                  = var.enable_pam
    pam_eligible_groups                         = var.pam_eligible_groups
    pam_approver_groups                         = var.pam_approver_groups
    pam_max_request_duration                    = var.pam_max_request_duration
    enable_scoped_access_policies               = var.enable_scoped_access_policies
    guardrail_owner_mode                        = var.guardrail_owner_mode
    prefer_managed_constraints                  = var.prefer_managed_constraints
    enable_log_analytics                        = var.enable_log_analytics
    log_analytics_retention_days                = var.log_analytics_retention_days
    enable_logging_organization_settings        = var.enable_logging_organization_settings
    logging_settings_kms_key_name               = var.logging_settings_kms_key_name
    enable_principal_access_boundary            = var.enable_principal_access_boundary
    principal_access_boundary_allowed_resources = var.principal_access_boundary_allowed_resources
    restrict_cloud_run_ingress                  = var.restrict_cloud_run_ingress
    org_policy_overrides                        = var.org_policy_overrides
    allowed_workload_identity_issuers           = var.allowed_workload_identity_issuers
    allowed_workload_identity_aws_accounts      = var.allowed_workload_identity_aws_accounts
    wif_tenant_pin_enforcement                  = var.wif_tenant_pin_enforcement
  }
  removed_inputs_set     = sort([for k, v in local.removed_inputs : k if v != null])
  removed_inputs_message = "Removed variables are set; move each into gcp_overrides (UPGRADING.md): ${join(", ", [for k in local.removed_inputs_set : "${k} -> gcp_overrides.${k}"])}."
}

# Fails the plan while any removed variable is set, naming its replacement.
resource "terraform_data" "removed_inputs_guard" {
  count = length(local.removed_inputs_set) > 0 ? 1 : 0

  lifecycle {
    precondition {
      condition     = length(local.removed_inputs_set) == 0
      error_message = local.removed_inputs_message
    }
  }
}
