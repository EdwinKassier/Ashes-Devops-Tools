# tflint-ignore-file: terraform_typed_variables, terraform_standard_module_structure
# (untyped on purpose so any old value type still reaches the guard; kept apart
# from variables.tf so the whole file goes at v1.0)

# Removed inputs (v0.2.0): every tuning input of this root moved into the
# aws_overrides object (UPGRADING.md, "Object pass-through"). The old names are
# declared again, untyped and inert, only so that a value still set in a tfvars
# file, a TFC workspace variable or a TF_VAR_ environment variable fails the
# plan instead of being ignored; `deprecated` also names the replacement in a
# warning on the same run. Removed at v1.0.

variable "aws_enabled_regions" {
  description = "REMOVED in v0.2.0: use aws_overrides.aws_enabled_regions."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.aws_enabled_regions instead. This declaration goes at v1.0."
  default     = null
}

variable "log_archive_bucket_name" {
  description = "REMOVED in v0.2.0: use aws_overrides.log_archive_bucket_name."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.log_archive_bucket_name instead. This declaration goes at v1.0."
  default     = null
}

variable "key_admin_arn" {
  description = "REMOVED in v0.2.0: use aws_overrides.key_admin_arn."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.key_admin_arn instead. This declaration goes at v1.0."
  default     = null
}

variable "key_admin_role_name" {
  description = "REMOVED in v0.2.0: use aws_overrides.key_admin_role_name."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.key_admin_role_name instead. This declaration goes at v1.0."
  default     = null
}

variable "kms_key_user_arns" {
  description = "REMOVED in v0.2.0: use aws_overrides.kms_key_user_arns."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.kms_key_user_arns instead. This declaration goes at v1.0."
  default     = null
}

variable "enable_kms_protection_tag" {
  description = "REMOVED in v0.2.0: use aws_overrides.enable_kms_protection_tag."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.enable_kms_protection_tag instead. This declaration goes at v1.0."
  default     = null
}

variable "config_role_arn" {
  description = "REMOVED in v0.2.0: use aws_overrides.config_role_arn."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.config_role_arn instead. This declaration goes at v1.0."
  default     = null
}

variable "create_config_service_linked_role" {
  description = "REMOVED in v0.2.0: use aws_overrides.create_config_service_linked_role."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.create_config_service_linked_role instead. This declaration goes at v1.0."
  default     = null
}

variable "aggregator_role_arn" {
  description = "REMOVED in v0.2.0: use aws_overrides.aggregator_role_arn."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.aggregator_role_arn instead. This declaration goes at v1.0."
  default     = null
}

variable "meta_store_manager_role_arn" {
  description = "REMOVED in v0.2.0: use aws_overrides.meta_store_manager_role_arn."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.meta_store_manager_role_arn instead. This declaration goes at v1.0."
  default     = null
}

variable "break_glass_role_arn" {
  description = "REMOVED in v0.2.0: use aws_overrides.break_glass_role_arn."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.break_glass_role_arn instead. This declaration goes at v1.0."
  default     = null
}

variable "notification_subscribers" {
  description = "REMOVED in v0.2.0: use aws_overrides.notification_subscribers."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.notification_subscribers instead. This declaration goes at v1.0."
  default     = null
}

variable "enabled_security_services" {
  description = "REMOVED in v0.2.0: use aws_overrides.enabled_security_services."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.enabled_security_services instead. This declaration goes at v1.0."
  default     = null
}

variable "config_record_all_supported" {
  description = "REMOVED in v0.2.0: use aws_overrides.config_record_all_supported."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.config_record_all_supported instead. This declaration goes at v1.0."
  default     = null
}

variable "guardduty_enable_ebs_malware_protection" {
  description = "REMOVED in v0.2.0: use aws_overrides.guardduty_enable_ebs_malware_protection."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.guardduty_enable_ebs_malware_protection instead. This declaration goes at v1.0."
  default     = null
}

variable "enable_security_lake" {
  description = "REMOVED in v0.2.0: use aws_overrides.enable_security_lake."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.enable_security_lake instead. This declaration goes at v1.0."
  default     = null
}

variable "enable_incident_response" {
  description = "REMOVED in v0.2.0: use aws_overrides.enable_incident_response."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.enable_incident_response instead. This declaration goes at v1.0."
  default     = null
}

variable "enable_service_quotas" {
  description = "REMOVED in v0.2.0: use aws_overrides.enable_service_quotas."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.enable_service_quotas instead. This declaration goes at v1.0."
  default     = null
}

variable "identity_account_id" {
  description = "REMOVED in v0.2.0: use aws_overrides.identity_account_id."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.identity_account_id instead. This declaration goes at v1.0."
  default     = null
}

variable "enable_cloudwatch_logs" {
  description = "REMOVED in v0.2.0: use aws_overrides.enable_cloudwatch_logs."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.enable_cloudwatch_logs instead. This declaration goes at v1.0."
  default     = null
}

variable "cloudwatch_logs_retention_days" {
  description = "REMOVED in v0.2.0: use aws_overrides.cloudwatch_logs_retention_days."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.cloudwatch_logs_retention_days instead. This declaration goes at v1.0."
  default     = null
}

variable "cloudwatch_logs_kms_key_arn" {
  description = "REMOVED in v0.2.0: use aws_overrides.cloudwatch_logs_kms_key_arn."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.cloudwatch_logs_kms_key_arn instead. This declaration goes at v1.0."
  default     = null
}

variable "cloudtrail_alarm_sns_topic_arn" {
  description = "REMOVED in v0.2.0: use aws_overrides.cloudtrail_alarm_sns_topic_arn."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.cloudtrail_alarm_sns_topic_arn instead. This declaration goes at v1.0."
  default     = null
}

variable "cloudtrail_alarm_subscribers" {
  description = "REMOVED in v0.2.0: use aws_overrides.cloudtrail_alarm_subscribers."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.cloudtrail_alarm_subscribers instead. This declaration goes at v1.0."
  default     = null
}

variable "cloudtrail_cis_alarms_excluded" {
  description = "REMOVED in v0.2.0: use aws_overrides.cloudtrail_cis_alarms_excluded."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.cloudtrail_cis_alarms_excluded instead. This declaration goes at v1.0."
  default     = null
}

variable "cloudtrail_s3_data_events" {
  description = "REMOVED in v0.2.0: use aws_overrides.cloudtrail_s3_data_events."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.cloudtrail_s3_data_events instead. This declaration goes at v1.0."
  default     = null
}

variable "cloudtrail_s3_data_events_excluded_bucket_arns" {
  description = "REMOVED in v0.2.0: use aws_overrides.cloudtrail_s3_data_events_excluded_bucket_arns."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.cloudtrail_s3_data_events_excluded_bucket_arns instead. This declaration goes at v1.0."
  default     = null
}

variable "cloudtrail_lambda_data_events" {
  description = "REMOVED in v0.2.0: use aws_overrides.cloudtrail_lambda_data_events."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.cloudtrail_lambda_data_events instead. This declaration goes at v1.0."
  default     = null
}

variable "create_break_glass" {
  description = "REMOVED in v0.2.0: use aws_overrides.create_break_glass."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.create_break_glass instead. This declaration goes at v1.0."
  default     = null
}

variable "break_glass_role_name" {
  description = "REMOVED in v0.2.0: use aws_overrides.break_glass_role_name."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.break_glass_role_name instead. This declaration goes at v1.0."
  default     = null
}

variable "break_glass_trusted_principals" {
  description = "REMOVED in v0.2.0: use aws_overrides.break_glass_trusted_principals."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.break_glass_trusted_principals instead. This declaration goes at v1.0."
  default     = null
}

variable "break_glass_mfa_max_age" {
  description = "REMOVED in v0.2.0: use aws_overrides.break_glass_mfa_max_age."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.break_glass_mfa_max_age instead. This declaration goes at v1.0."
  default     = null
}

variable "break_glass_active" {
  description = "REMOVED in v0.2.0: use aws_overrides.break_glass_active."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.break_glass_active instead. This declaration goes at v1.0."
  default     = null
}

variable "create_organization_trail" {
  description = "REMOVED in v0.2.0: use aws_overrides.create_organization_trail."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.create_organization_trail instead. This declaration goes at v1.0."
  default     = null
}

variable "cloudtrail_cloudwatch_role_arn" {
  description = "REMOVED in v0.2.0: use aws_overrides.cloudtrail_cloudwatch_role_arn."
  deprecated  = "Removed in v0.2.0 (the plan fails while it is set): set aws_overrides.cloudtrail_cloudwatch_role_arn instead. This declaration goes at v1.0."
  default     = null
}

locals {
  # Removed variable name => its value (null unless still set).
  removed_inputs = {
    aws_enabled_regions                            = var.aws_enabled_regions
    log_archive_bucket_name                        = var.log_archive_bucket_name
    key_admin_arn                                  = var.key_admin_arn
    key_admin_role_name                            = var.key_admin_role_name
    kms_key_user_arns                              = var.kms_key_user_arns
    enable_kms_protection_tag                      = var.enable_kms_protection_tag
    config_role_arn                                = var.config_role_arn
    create_config_service_linked_role              = var.create_config_service_linked_role
    aggregator_role_arn                            = var.aggregator_role_arn
    meta_store_manager_role_arn                    = var.meta_store_manager_role_arn
    break_glass_role_arn                           = var.break_glass_role_arn
    notification_subscribers                       = var.notification_subscribers
    enabled_security_services                      = var.enabled_security_services
    config_record_all_supported                    = var.config_record_all_supported
    guardduty_enable_ebs_malware_protection        = var.guardduty_enable_ebs_malware_protection
    enable_security_lake                           = var.enable_security_lake
    enable_incident_response                       = var.enable_incident_response
    enable_service_quotas                          = var.enable_service_quotas
    identity_account_id                            = var.identity_account_id
    enable_cloudwatch_logs                         = var.enable_cloudwatch_logs
    cloudwatch_logs_retention_days                 = var.cloudwatch_logs_retention_days
    cloudwatch_logs_kms_key_arn                    = var.cloudwatch_logs_kms_key_arn
    cloudtrail_alarm_sns_topic_arn                 = var.cloudtrail_alarm_sns_topic_arn
    cloudtrail_alarm_subscribers                   = var.cloudtrail_alarm_subscribers
    cloudtrail_cis_alarms_excluded                 = var.cloudtrail_cis_alarms_excluded
    cloudtrail_s3_data_events                      = var.cloudtrail_s3_data_events
    cloudtrail_s3_data_events_excluded_bucket_arns = var.cloudtrail_s3_data_events_excluded_bucket_arns
    cloudtrail_lambda_data_events                  = var.cloudtrail_lambda_data_events
    create_break_glass                             = var.create_break_glass
    break_glass_role_name                          = var.break_glass_role_name
    break_glass_trusted_principals                 = var.break_glass_trusted_principals
    break_glass_mfa_max_age                        = var.break_glass_mfa_max_age
    break_glass_active                             = var.break_glass_active
    create_organization_trail                      = var.create_organization_trail
    cloudtrail_cloudwatch_role_arn                 = var.cloudtrail_cloudwatch_role_arn
  }
  removed_inputs_set     = sort([for k, v in local.removed_inputs : k if v != null])
  removed_inputs_message = "Removed variables are set; move each into aws_overrides (UPGRADING.md): ${join(", ", [for k in local.removed_inputs_set : "${k} -> aws_overrides.${k}"])}."
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
