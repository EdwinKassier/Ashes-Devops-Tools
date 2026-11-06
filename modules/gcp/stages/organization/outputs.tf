output "folders" {
  description = "Map of created folders"
  value       = module.organization.folders
}

output "organization_id" {
  description = "Organization ID"
  value       = module.organization.organization_id
}

output "tag_keys" {
  description = "Tag keys available to downstream consumers"
  value       = module.tags.tag_keys
}

output "tag_value_ids" {
  description = "Tag values available to downstream consumers"
  value       = module.tags.tag_values
}

output "audit_logs_bucket_name" {
  description = "Name of the Cloud Storage bucket receiving audit logs"
  value       = module.audit_logs.storage_bucket_name
}

output "billing_export_dataset_id" {
  description = "BigQuery dataset ID for Cloud Billing export data"
  value       = google_bigquery_dataset.billing_export.dataset_id
}

output "scc_pubsub_topic_id" {
  description = "Pub/Sub topic ID receiving Security Command Center findings notifications"
  value       = module.scc_notifications.topic_id
}

output "cmek_key_names" {
  description = "Map of KMS key short names to fully qualified key resource IDs created by the CMEK modules (org keyring plus, when logging_project_id is set, the audit keyring in the logging project)"
  value       = merge(module.cmek.key_names, local.separate_logging_project ? module.audit_cmek[0].key_names : {})
}

output "audit_project_id" {
  description = "Project holding the org audit bucket, audit CMEK and control-plane alerts (logging_project_id, or the admin project when unset)"
  value       = local.audit_project_id
}

output "control_plane_alert_policy_ids" {
  description = "Map of control-plane watch name to alert policy ID (empty when enable_control_plane_alerting = false)"
  value       = module.control_plane_alerting.watch_alert_policy_ids
}

output "admin_containment_rules" {
  description = "Rules of the admin-containment IAM deny policy (empty when enable_admin_containment = false): denied permissions, exempt principals and whether the rule is tag-scoped to the audit store."
  value = flatten([
    for p in local.containment_deny_policy : [
      for r in p.rules : {
        description          = r.description
        denied_permissions   = r.denied_permissions
        exception_principals = r.exception_principals
        tag_scoped           = r.denial_condition != null
      }
    ]
  ])
}

output "audit_org_sink_name" {
  description = "Name of the org-level audit-log sink that exports to the audit bucket"
  value       = module.audit_logs.org_log_sink_name
}

output "org_policy_constraints" {
  description = "Org-node policy constraints this stage manages (boolean + list), for downstream verification"
  value       = sort(concat(keys(module.org_policies.boolean_policy_names), keys(module.org_policies.list_policy_names)))
}

output "strict_folder_policy_environment_keys" {
  description = "Environment folders that received the strict folder org-policy bundle"
  value       = sort(keys(module.prod_folder_policies))
}

output "control_plane_watched_names" {
  description = "Names of the active control-plane alert watches"
  value       = module.control_plane_alerting.watched_names
}

output "control_plane_org_log_route_sink_name" {
  description = "Aggregated org sink routing Admin Activity logs to the alerting project (null when alerting is off)"
  value       = module.control_plane_alerting.org_log_route_sink_name
}

output "iam_deny_policy_names" {
  description = "Names of the IAM deny policies planned at the org node (containment + iam_deny_policies)"
  value       = module.iam_deny.deny_policy_names
}

output "os_login_exempt_environment_keys" {
  description = "Environment folders exempted from the org-wide OS Login requirement (empty when none, or when enforce_os_login = false)"
  value       = sort(keys(module.os_login_exemptions))
}

output "control_plane_cis_log_metric_names" {
  description = "Map of CIS GCP 2.4-2.11 log-metric key to log-based metric name in the alerting project (empty when disabled)"
  value       = module.control_plane_alerting.cis_log_metric_names
}

output "scoped_access_policy_ids" {
  description = "Map of environment key -> numeric ID of its folder-scoped Access Context Manager policy (empty when enable_scoped_access_policies = false). gcp-projects surfaces it as environment_config[<env>].vpc_sc_access_policy_id for the workload perimeter."
  value       = { for k, p in google_access_context_manager_access_policy.environment : k => p.name }
}

output "scoped_access_policy_grants" {
  description = "Workload SA grants on the scoped access policies, keyed \"<env>|<phase>\": { env, role, member }."
  value       = local.scoped_policy_grants
}

output "delegated_folder_iam_targets" {
  description = "Folders on which projects-apply holds the conditional folderIamAdmin, keyed by folder key, with the role allow-list of each."
  value       = local.delegated_folder_iam_targets
}

output "org_admin_members" {
  description = "Principals holding standing roles/resourcemanager.organizationAdmin (groups only unless allow_user_principals_for_break_glass = true)."
  value       = local.org_admin_members
}

output "billing_admin_members" {
  description = "Principals holding standing roles/billing.admin (groups only unless allow_user_principals_for_break_glass = true)."
  value       = local.billing_admin_members
}

output "pam_entitlement_name" {
  description = "Resource name of the just-in-time org-admin PAM entitlement (null when enable_pam = false)."
  value       = var.enable_pam ? google_privileged_access_manager_entitlement.org_admin[0].name : null
}

output "production_environment_keys" {
  description = "Environment keys marked is_production = true."
  value       = local.production_environment_keys
}
