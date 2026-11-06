# Billing Account
output "billing_account" {
  description = "Billing account ID for downstream usage"
  value       = data.google_billing_account.billing.id
}

# Admin Project
output "admin_project" {
  description = "Details of the admin project"
  value = {
    project_id = local.bootstrap.admin_project_id
    number     = local.bootstrap.admin_project_number
  }
}

# Admin Project Number (for VPC-SC ingress policies referencing Workload Identity)
output "admin_project_number" {
  description = "Admin project number for Workload Identity pool references"
  value       = local.bootstrap.admin_project_number
}

# Organization Details
output "organization" {
  description = "Organization details"
  value = {
    id = module.organization.organization_id
  }
}

# Organization ID (for VPC-SC and other resources requiring org_id)
output "org_id" {
  description = "Organization ID for downstream resource configuration"
  value       = module.organization.organization_id
}

# Folders
output "folders" {
  description = "Map of created folders"
  value       = module.organization.folders
}

# Projects, environment_config and hub_network moved to the gcp-projects and
# gcp-network-hub roots when those stages were split out. Downstream
# gcp-workload reads environment_config from gcp-projects and hub_network from
# gcp-network-hub.

# Environment Variables
output "project_prefix" {
  description = "Project prefix used for naming"
  value       = local.project_prefix
}

output "organization_name" {
  description = "Name of the organization"
  value       = local.organization_name
}

output "default_region" {
  description = "Default region for resources"
  value       = local.default_region
}

# Service Accounts
output "terraform_service_account_email" {
  description = "Email of the Terraform Admin Service Account"
  value       = local.bootstrap.terraform_admin_email
}

# Workload Identity Federation — needed by GitHub Actions and Terraform Cloud after bootstrap
output "github_oidc_pool_id" {
  description = "Workload Identity Pool ID for GitHub Actions OIDC"
  value       = try(local.bootstrap.github_oidc_pool_id, null)
}

output "github_oidc_provider_name" {
  description = "Fully-qualified WIF provider name for use in GitHub Actions (google-github-actions/auth)"
  value       = try(local.bootstrap.github_oidc_provider_name, null)
}

output "tfc_oidc_pool_id" {
  description = "Workload Identity Pool ID for Terraform Cloud OIDC (null if TFC OIDC not configured)"
  value       = try(local.bootstrap.tfc_oidc_pool_id, null)
}

output "tfc_oidc_provider_name" {
  description = "Fully-qualified WIF provider name for Terraform Cloud OIDC (null if TFC OIDC not configured)"
  value       = try(local.bootstrap.tfc_oidc_provider_name, null)
}

# Tag Values (for downstream usage)
output "tag_values" {
  description = "Map of available Resource Manager Tag Values"
  value       = module.organization.tag_value_ids
}

# Tag Keys — needed by envs/gcp/workload to bind tags to resources downstream
output "tag_keys" {
  description = "Map of tag key short names to their Resource Manager resource IDs"
  value       = module.organization.tag_keys
}

# Audit & compliance outputs — consumed by downstream monitoring/SIEM configuration
output "audit_logs_bucket_name" {
  description = "Cloud Storage bucket receiving organization-wide audit logs"
  value       = module.organization.audit_logs_bucket_name
}

output "billing_export_dataset_id" {
  description = "BigQuery dataset ID for Cloud Billing export"
  value       = module.organization.billing_export_dataset_id
}

output "scc_pubsub_topic_id" {
  description = "Pub/Sub topic receiving Security Command Center findings"
  value       = module.organization.scc_pubsub_topic_id
}

output "cmek_key_names" {
  description = "Map of CMEK key short-name to key ID created by the organization stage. Lets downstream roots (e.g. gcp/workload) encrypt resources with org-managed keys via remote state. Re-exports modules/gcp/stages/organization output cmek_key_names."
  value       = module.organization.cmek_key_names
}

output "audit_project_id" {
  description = "Project holding the org audit bucket, audit CMEK and control-plane alerts (logging_project_id, or the admin project)."
  value       = module.organization.audit_project_id
}

output "control_plane_alert_policy_ids" {
  description = "Map of control-plane watch name to alert policy ID."
  value       = module.organization.control_plane_alert_policy_ids
}

# Per-environment folder-scoped access policies, surfaced by gcp-projects as
# environment_config[<env>].vpc_sc_access_policy_id for the workload perimeter.
output "scoped_access_policy_ids" {
  description = "Map of environment key -> numeric ID of its folder-scoped Access Context Manager policy."
  value       = module.organization.scoped_access_policy_ids
}

output "delegated_folder_iam_targets" {
  description = "Folders on which the gcp-projects apply SA holds the conditional folderIamAdmin, with each folder's role allow-list."
  value       = module.organization.delegated_folder_iam_targets
}

output "pam_entitlement_name" {
  description = "Resource name of the just-in-time org-admin PAM entitlement (null when enable_pam = false)."
  value       = module.organization.pam_entitlement_name
}

output "guardrail_owner_mode" {
  description = "Deny-policy ownership: \"separate\" (apply guardrail_deny_policy_specs as the guardrail owner) or \"organization\" (applied by this root)."
  value       = module.organization.guardrail_owner_mode
}

output "guardrail_deny_policy_specs" {
  description = "Map of org deny-policy ID => gcloud policy-file JSON (containment + iam_deny_policies). In separate mode, apply each as the guardrails SA: see docs/runbooks/production-hardening.md."
  value       = module.organization.guardrail_deny_policy_specs
}

output "log_analytics_bucket_id" {
  description = "Audit Log Analytics bucket (null when disabled)."
  value       = module.organization.log_analytics_bucket_id
}

output "principal_access_boundary_policy" {
  description = "Automation principal access boundary policy name (null when disabled)."
  value       = module.organization.principal_access_boundary_policy
}

# Containment defaults ON for a production estate; the derived settings are
# validated here (a variable validation cannot read the derived locals without
# a cycle). A failed precondition fails the plan.
output "admin_containment_enabled" {
  description = "Whether the admin-containment deny policy is on (explicit enable_admin_containment, else gcp.admin_containment, else on when any environment is_production)."
  value       = local.enable_admin_containment

  precondition {
    condition     = !local.enable_admin_containment || length(local.containment_exempt_principals) > 0
    error_message = "Admin containment is on (it defaults on when an environment is_production) but no break-glass principal is set, so the deny would lock out everyone. Set gcp.break_glass_group in config/landing-zone.yaml (or containment_exempt_principals), or set enable_admin_containment = false explicitly to run production without it."
  }

  precondition {
    condition     = !anytrue([for p in local.containment_exempt_principals : can(regex("(?i)(replace-me|your-domain|example\\.(com|org|net)|\\.invalid$|changeme)", p))])
    error_message = "The break-glass principal (gcp.break_glass_group / containment_exempt_principals) is still a placeholder. Set your real break-glass group."
  }
}
