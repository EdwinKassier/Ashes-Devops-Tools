# Removed inputs (v0.2.0): every tuning input of this root moved into the
# gcp_overrides object (UPGRADING.md, "Object pass-through"). The old names are
# declared again, untyped and inert, only so that a value still set in a tfvars
# file, a TFC workspace variable or a TF_VAR_ environment variable fails the
# plan instead of being ignored. Removed at v1.0.

variable "admin_email" {
  description = "REMOVED in v0.2.0: use gcp_overrides.admin_email."
  default     = null
}

variable "break_glass_user" {
  description = "REMOVED in v0.2.0: use gcp_overrides.break_glass_user."
  default     = null
}

variable "organization_admin_groups" {
  description = "REMOVED in v0.2.0: use gcp_overrides.organization_admin_groups."
  default     = null
}

variable "billing_admin_groups" {
  description = "REMOVED in v0.2.0: use gcp_overrides.billing_admin_groups."
  default     = null
}

variable "allowed_regions" {
  description = "REMOVED in v0.2.0: use gcp_overrides.allowed_regions."
  default     = null
}

variable "strict_folder_policy_environment_keys" {
  description = "REMOVED in v0.2.0: use gcp_overrides.strict_folder_policy_environment_keys."
  default     = null
}

variable "security_contact_email" {
  description = "REMOVED in v0.2.0: use gcp_overrides.security_contact_email."
  default     = null
}

variable "billing_contact_email" {
  description = "REMOVED in v0.2.0: use gcp_overrides.billing_contact_email."
  default     = null
}

variable "budget_currency" {
  description = "REMOVED in v0.2.0: use gcp_overrides.budget_currency."
  default     = null
}

variable "custom_org_constraints" {
  description = "REMOVED in v0.2.0: use gcp_overrides.custom_org_constraints."
  default     = null
}

variable "enable_audit_bucket_lock" {
  description = "REMOVED in v0.2.0: use gcp_overrides.enable_audit_bucket_lock."
  default     = null
}

variable "iam_deny_policies" {
  description = "REMOVED in v0.2.0: use gcp_overrides.iam_deny_policies."
  default     = null
}

variable "logging_project_id" {
  description = "REMOVED in v0.2.0: use gcp_overrides.logging_project_id."
  default     = null
}

variable "logging_project_number" {
  description = "REMOVED in v0.2.0: use gcp_overrides.logging_project_number."
  default     = null
}

variable "audit_soft_delete_retention_days" {
  description = "REMOVED in v0.2.0: use gcp_overrides.audit_soft_delete_retention_days."
  default     = null
}

variable "enforce_os_login" {
  description = "REMOVED in v0.2.0: use gcp_overrides.enforce_os_login."
  default     = null
}

variable "os_login_exempt_environment_keys" {
  description = "REMOVED in v0.2.0: use gcp_overrides.os_login_exempt_environment_keys."
  default     = null
}

variable "enable_cis_log_metrics" {
  description = "REMOVED in v0.2.0: use gcp_overrides.enable_cis_log_metrics."
  default     = null
}

variable "enable_control_plane_alerting" {
  description = "REMOVED in v0.2.0: use gcp_overrides.enable_control_plane_alerting."
  default     = null
}

variable "alert_notification_emails" {
  description = "REMOVED in v0.2.0: use gcp_overrides.alert_notification_emails."
  default     = null
}

variable "alert_notification_channels" {
  description = "REMOVED in v0.2.0: use gcp_overrides.alert_notification_channels."
  default     = null
}

variable "break_glass_principal_emails" {
  description = "REMOVED in v0.2.0: use gcp_overrides.break_glass_principal_emails."
  default     = null
}

variable "enable_cmek_org_policy" {
  description = "REMOVED in v0.2.0: use gcp_overrides.enable_cmek_org_policy."
  default     = null
}

variable "cmek_required_services" {
  description = "REMOVED in v0.2.0: use gcp_overrides.cmek_required_services."
  default     = null
}

variable "enable_admin_containment" {
  description = "REMOVED in v0.2.0: use gcp_overrides.enable_admin_containment."
  default     = null
}

variable "containment_exempt_principals" {
  description = "REMOVED in v0.2.0: use gcp_overrides.containment_exempt_principals."
  default     = null
}

variable "enable_legacy_admin_folder_roles" {
  description = "REMOVED in v0.2.0: use gcp_overrides.enable_legacy_admin_folder_roles."
  default     = null
}

variable "allow_user_principals_for_break_glass" {
  description = "REMOVED in v0.2.0: use gcp_overrides.allow_user_principals_for_break_glass."
  default     = null
}

variable "enable_pam" {
  description = "REMOVED in v0.2.0: use gcp_overrides.enable_pam."
  default     = null
}

variable "pam_eligible_groups" {
  description = "REMOVED in v0.2.0: use gcp_overrides.pam_eligible_groups."
  default     = null
}

variable "pam_approver_groups" {
  description = "REMOVED in v0.2.0: use gcp_overrides.pam_approver_groups."
  default     = null
}

variable "pam_max_request_duration" {
  description = "REMOVED in v0.2.0: use gcp_overrides.pam_max_request_duration."
  default     = null
}

variable "enable_scoped_access_policies" {
  description = "REMOVED in v0.2.0: use gcp_overrides.enable_scoped_access_policies."
  default     = null
}

variable "guardrail_owner_mode" {
  description = "REMOVED in v0.2.0: use gcp_overrides.guardrail_owner_mode."
  default     = null
}

variable "prefer_managed_constraints" {
  description = "REMOVED in v0.2.0: use gcp_overrides.prefer_managed_constraints."
  default     = null
}

variable "enable_log_analytics" {
  description = "REMOVED in v0.2.0: use gcp_overrides.enable_log_analytics."
  default     = null
}

variable "log_analytics_retention_days" {
  description = "REMOVED in v0.2.0: use gcp_overrides.log_analytics_retention_days."
  default     = null
}

variable "enable_logging_organization_settings" {
  description = "REMOVED in v0.2.0: use gcp_overrides.enable_logging_organization_settings."
  default     = null
}

variable "logging_settings_kms_key_name" {
  description = "REMOVED in v0.2.0: use gcp_overrides.logging_settings_kms_key_name."
  default     = null
}

variable "enable_principal_access_boundary" {
  description = "REMOVED in v0.2.0: use gcp_overrides.enable_principal_access_boundary."
  default     = null
}

variable "principal_access_boundary_allowed_resources" {
  description = "REMOVED in v0.2.0: use gcp_overrides.principal_access_boundary_allowed_resources."
  default     = null
}

variable "restrict_cloud_run_ingress" {
  description = "REMOVED in v0.2.0: use gcp_overrides.restrict_cloud_run_ingress."
  default     = null
}

variable "org_policy_overrides" {
  description = "REMOVED in v0.2.0: use gcp_overrides.org_policy_overrides."
  default     = null
}

variable "allowed_workload_identity_issuers" {
  description = "REMOVED in v0.2.0: use gcp_overrides.allowed_workload_identity_issuers."
  default     = null
}

variable "allowed_workload_identity_aws_accounts" {
  description = "REMOVED in v0.2.0: use gcp_overrides.allowed_workload_identity_aws_accounts."
  default     = null
}

variable "wif_tenant_pin_enforcement" {
  description = "REMOVED in v0.2.0: use gcp_overrides.wif_tenant_pin_enforcement."
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
