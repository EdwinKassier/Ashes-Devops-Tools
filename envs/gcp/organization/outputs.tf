# Billing Account
locals {
  # The gcp-organization cross-root contract: ONE non-sensitive object that downstream
  # roots read as .outputs.contract (tfc-admin: tfe_outputs nonsensitive_values
  # .contract). Never put a sensitive value in it: one sensitive attribute moves
  # the whole object into tfe_outputs' sensitive_values. Keys are stable;
  # scripts/check-contracts.sh enforces the read side.
  contract = {
    billing_account = data.google_billing_account.billing.id
    admin_project = {
      project_id = local.bootstrap.admin_project_id
      number     = local.bootstrap.admin_project_number
    }
    admin_project_number = local.bootstrap.admin_project_number
    organization = {
      id = module.organization.organization_id
    }
    org_id                           = module.organization.organization_id
    folders                          = module.organization.folders
    project_prefix                   = local.project_prefix
    organization_name                = local.organization_name
    default_region                   = local.default_region
    terraform_service_account_email  = local.bootstrap.terraform_admin_email
    github_oidc_pool_id              = try(local.bootstrap.github_oidc_pool_id, null)
    github_oidc_provider_name        = try(local.bootstrap.github_oidc_provider_name, null)
    tfc_oidc_pool_id                 = try(local.bootstrap.tfc_oidc_pool_id, null)
    tfc_oidc_provider_name           = try(local.bootstrap.tfc_oidc_provider_name, null)
    tag_values                       = module.organization.tag_value_ids
    tag_keys                         = module.organization.tag_keys
    audit_logs_bucket_name           = module.organization.audit_logs_bucket_name
    billing_export_dataset_id        = module.organization.billing_export_dataset_id
    scc_pubsub_topic_id              = module.organization.scc_pubsub_topic_id
    cmek_key_names                   = module.organization.cmek_key_names
    audit_project_id                 = module.organization.audit_project_id
    control_plane_alert_policy_ids   = module.organization.control_plane_alert_policy_ids
    scoped_access_policy_ids         = module.organization.scoped_access_policy_ids
    delegated_folder_iam_targets     = module.organization.delegated_folder_iam_targets
    pam_entitlement_name             = module.organization.pam_entitlement_name
    guardrail_owner_mode             = module.organization.guardrail_owner_mode
    guardrail_deny_policy_specs      = module.organization.guardrail_deny_policy_specs
    log_analytics_bucket_id          = module.organization.log_analytics_bucket_id
    principal_access_boundary_policy = module.organization.principal_access_boundary_policy
    admin_containment_enabled        = local.enable_admin_containment
  }
}

output "contract" {
  description = "The gcp-organization cross-root contract: every key below in one non-sensitive object. Downstream roots read this output only; the individual outputs are deprecated aliases kept until v1.0."
  value       = local.contract

  # Admin-containment guards. They live on the contract output (not the
  # deprecated admin_containment_enabled alias) so they outlive its v1.0 removal.
  precondition {
    condition     = !local.enable_admin_containment || length(local.containment_exempt_principals) > 0
    error_message = "Admin containment is on (it defaults on when an environment is_production) but no break-glass principal is set, so the deny would lock out everyone. Set gcp.break_glass_group in config/landing-zone.yaml (or containment_exempt_principals), or set enable_admin_containment = false explicitly to run production without it."
  }

  precondition {
    condition     = !anytrue([for p in local.containment_exempt_principals : can(regex("(?i)(replace-me|your-domain|example\\.(com|org|net)|\\.invalid$|changeme)", p))])
    error_message = "The break-glass principal (gcp.break_glass_group / containment_exempt_principals) is still a placeholder. Set your real break-glass group."
  }
}

output "billing_account" {
  description = "Deprecated: read contract.billing_account (removed in v1.0). Billing account ID for downstream usage"
  value       = local.contract.billing_account
}

# Admin Project
output "admin_project" {
  description = "Deprecated: read contract.admin_project (removed in v1.0). Details of the admin project"
  value       = local.contract.admin_project
}

# Admin Project Number (for VPC-SC ingress policies referencing Workload Identity)
output "admin_project_number" {
  description = "Deprecated: read contract.admin_project_number (removed in v1.0). Admin project number for Workload Identity pool references"
  value       = local.contract.admin_project_number
}

# Organization Details
output "organization" {
  description = "Deprecated: read contract.organization (removed in v1.0). Organization details"
  value       = local.contract.organization
}

# Organization ID (for VPC-SC and other resources requiring org_id)
output "org_id" {
  description = "Deprecated: read contract.org_id (removed in v1.0). Organization ID for downstream resource configuration"
  value       = local.contract.org_id
}

# Folders
output "folders" {
  description = "Deprecated: read contract.folders (removed in v1.0). Map of created folders"
  value       = local.contract.folders
}

# Projects, environment_config and hub_network moved to the gcp-projects and
# gcp-network-hub roots when those stages were split out. Downstream
# gcp-workload reads environment_config from gcp-projects and hub_network from
# gcp-network-hub.

# Environment Variables
output "project_prefix" {
  description = "Deprecated: read contract.project_prefix (removed in v1.0). Project prefix used for naming"
  value       = local.contract.project_prefix
}

output "organization_name" {
  description = "Deprecated: read contract.organization_name (removed in v1.0). Name of the organization"
  value       = local.contract.organization_name
}

output "default_region" {
  description = "Deprecated: read contract.default_region (removed in v1.0). Default region for resources"
  value       = local.contract.default_region
}

# Service Accounts
output "terraform_service_account_email" {
  description = "Deprecated: read contract.terraform_service_account_email (removed in v1.0). Email of the Terraform Admin Service Account"
  value       = local.contract.terraform_service_account_email
}

# Workload Identity Federation — needed by GitHub Actions and Terraform Cloud after bootstrap
output "github_oidc_pool_id" {
  description = "Deprecated: read contract.github_oidc_pool_id (removed in v1.0). Workload Identity Pool ID for GitHub Actions OIDC"
  value       = local.contract.github_oidc_pool_id
}

output "github_oidc_provider_name" {
  description = "Deprecated: read contract.github_oidc_provider_name (removed in v1.0). Fully-qualified WIF provider name for use in GitHub Actions (google-github-actions/auth)"
  value       = local.contract.github_oidc_provider_name
}

output "tfc_oidc_pool_id" {
  description = "Deprecated: read contract.tfc_oidc_pool_id (removed in v1.0). Workload Identity Pool ID for Terraform Cloud OIDC (null if TFC OIDC not configured)"
  value       = local.contract.tfc_oidc_pool_id
}

output "tfc_oidc_provider_name" {
  description = "Deprecated: read contract.tfc_oidc_provider_name (removed in v1.0). Fully-qualified WIF provider name for Terraform Cloud OIDC (null if TFC OIDC not configured)"
  value       = local.contract.tfc_oidc_provider_name
}

# Tag Values (for downstream usage)
output "tag_values" {
  description = "Deprecated: read contract.tag_values (removed in v1.0). Map of available Resource Manager Tag Values"
  value       = local.contract.tag_values
}

# Tag Keys — needed by envs/gcp/workload to bind tags to resources downstream
output "tag_keys" {
  description = "Deprecated: read contract.tag_keys (removed in v1.0). Map of tag key short names to their Resource Manager resource IDs"
  value       = local.contract.tag_keys
}

# Audit & compliance outputs — consumed by downstream monitoring/SIEM configuration
output "audit_logs_bucket_name" {
  description = "Deprecated: read contract.audit_logs_bucket_name (removed in v1.0). Cloud Storage bucket receiving organization-wide audit logs"
  value       = local.contract.audit_logs_bucket_name
}

output "billing_export_dataset_id" {
  description = "Deprecated: read contract.billing_export_dataset_id (removed in v1.0). BigQuery dataset ID for Cloud Billing export"
  value       = local.contract.billing_export_dataset_id
}

output "scc_pubsub_topic_id" {
  description = "Deprecated: read contract.scc_pubsub_topic_id (removed in v1.0). Pub/Sub topic receiving Security Command Center findings"
  value       = local.contract.scc_pubsub_topic_id
}

output "cmek_key_names" {
  description = "Deprecated: read contract.cmek_key_names (removed in v1.0). Map of CMEK key short-name to key ID created by the organization stage. Lets downstream roots (e.g. gcp/workload) encrypt resources with org-managed keys via remote state. Re-exports modules/gcp/stages/organization output cmek_key_names."
  value       = local.contract.cmek_key_names
}

output "audit_project_id" {
  description = "Deprecated: read contract.audit_project_id (removed in v1.0). Project holding the org audit bucket, audit CMEK and control-plane alerts (logging_project_id, or the admin project)."
  value       = local.contract.audit_project_id
}

output "control_plane_alert_policy_ids" {
  description = "Deprecated: read contract.control_plane_alert_policy_ids (removed in v1.0). Map of control-plane watch name to alert policy ID."
  value       = local.contract.control_plane_alert_policy_ids
}

# Per-environment folder-scoped access policies, surfaced by gcp-projects as
# environment_config[<env>].vpc_sc_access_policy_id for the workload perimeter.
output "scoped_access_policy_ids" {
  description = "Deprecated: read contract.scoped_access_policy_ids (removed in v1.0). Map of environment key -> numeric ID of its folder-scoped Access Context Manager policy."
  value       = local.contract.scoped_access_policy_ids
}

output "delegated_folder_iam_targets" {
  description = "Deprecated: read contract.delegated_folder_iam_targets (removed in v1.0). Folders on which the gcp-projects apply SA holds the conditional folderIamAdmin, with each folder's role allow-list."
  value       = local.contract.delegated_folder_iam_targets
}

output "pam_entitlement_name" {
  description = "Deprecated: read contract.pam_entitlement_name (removed in v1.0). Resource name of the just-in-time org-admin PAM entitlement (null when enable_pam = false)."
  value       = local.contract.pam_entitlement_name
}

output "guardrail_owner_mode" {
  description = "Deprecated: read contract.guardrail_owner_mode (removed in v1.0). Deny-policy ownership: \"separate\" (authored and applied by the gcp-guardrails root) or \"organization\" (legacy: applied by this root)."
  value       = local.contract.guardrail_owner_mode
}

output "guardrail_deny_policy_specs" {
  description = "Deprecated: read contract.guardrail_deny_policy_specs (removed in v1.0). DEPRECATED (removed in v1.0). gcloud policy-file JSON of the deny policies this root applies in the legacy organization mode; empty in separate mode, where gcp-guardrails owns them (its deny_policy_specs output serves the break-glass path)."
  value       = local.contract.guardrail_deny_policy_specs
}

output "log_analytics_bucket_id" {
  description = "Deprecated: read contract.log_analytics_bucket_id (removed in v1.0). Audit Log Analytics bucket (null when disabled)."
  value       = local.contract.log_analytics_bucket_id
}

output "principal_access_boundary_policy" {
  description = "Deprecated: read contract.principal_access_boundary_policy (removed in v1.0). Automation principal access boundary policy name (null when disabled)."
  value       = local.contract.principal_access_boundary_policy
}

# Containment defaults ON for a production estate; the derived settings are
# validated here (a variable validation cannot read the derived locals without
# a cycle). A failed precondition fails the plan.
output "admin_containment_enabled" {
  description = "Deprecated: read contract.admin_containment_enabled (removed in v1.0). Whether the admin-containment deny policy is on (explicit enable_admin_containment, else gcp.admin_containment, else on when any environment is_production)."
  value       = local.contract.admin_containment_enabled
}
