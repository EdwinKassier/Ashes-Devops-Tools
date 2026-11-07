# Cross-root contract (Convention 4). Consumed by gcp-organization (and future
# gcp control-plane roots) via terraform_remote_state. Keep these keys stable
# across refactors — renaming one breaks the downstream root at plan.

locals {
  # The gcp-bootstrap cross-root contract: ONE non-sensitive object that downstream
  # roots read as .outputs.contract (tfc-admin: tfe_outputs nonsensitive_values
  # .contract). Never put a sensitive value in it: one sensitive attribute moves
  # the whole object into tfe_outputs' sensitive_values. Keys are stable;
  # scripts/check-contracts.sh enforces the read side.
  contract = {
    admin_project_id                    = module.bootstrap.admin_project_id
    admin_project_number                = module.bootstrap.admin_project_number
    terraform_admin_email               = module.bootstrap.terraform_admin_email
    suffix                              = module.bootstrap.suffix
    github_oidc_pool_id                 = module.bootstrap.github_oidc_pool_id
    github_oidc_pool_name               = module.bootstrap.github_oidc_pool_name
    github_oidc_provider_name           = module.bootstrap.github_oidc_provider_name
    tfc_oidc_pool_id                    = module.bootstrap.tfc_oidc_pool_id
    tfc_oidc_pool_name                  = module.bootstrap.tfc_oidc_pool_name
    tfc_oidc_provider_name              = module.bootstrap.tfc_oidc_provider_name
    resman_email                        = module.bootstrap.resman_email
    tfc_plan_service_accounts           = module.bootstrap.tfc_plan_service_accounts
    tfc_apply_service_accounts          = module.bootstrap.tfc_apply_service_accounts
    tfc_workload_provider_name          = module.bootstrap.tfc_workload_provider_name
    stage_service_accounts              = module.bootstrap.stage_service_accounts
    workload_service_accounts           = module.bootstrap.workload_service_accounts
    workload_folder_roles               = module.bootstrap.workload_folder_roles
    network_folder_roles                = module.bootstrap.network_folder_roles
    delegated_workload_folder_roles     = module.bootstrap.delegated_workload_folder_roles
    delegated_network_folder_roles      = module.bootstrap.delegated_network_folder_roles
    plan_viewer_role                    = module.bootstrap.plan_viewer_role
    production_workspaces_bound_by_name = module.bootstrap.production_workspaces_bound_by_name
    guardrail_owner_mode                = module.bootstrap.guardrail_owner_mode
    guardrails_service_account          = module.bootstrap.guardrails_service_account
    guardrails_plan_service_account     = module.bootstrap.guardrails_plan_service_account
    guardrails_workspace_bound_by_id    = module.bootstrap.guardrails_workspace_bound_by_id
  }
}

output "contract" {
  description = "The gcp-bootstrap cross-root contract: every key below in one non-sensitive object. Downstream roots read this output only; the individual outputs are deprecated aliases kept until v1.0."
  value       = local.contract
}

output "admin_project_id" {
  description = "Deprecated: read contract.admin_project_id (removed in v1.0). The admin (seed) project ID that hosts the Terraform admin SA and WIF pools."
  value       = local.contract.admin_project_id
}

output "admin_project_number" {
  description = "Deprecated: read contract.admin_project_number (removed in v1.0). The admin project number, used by WIF pool references and VPC-SC ingress policies."
  value       = local.contract.admin_project_number
}

output "terraform_admin_email" {
  description = "Deprecated: read contract.terraform_admin_email (removed in v1.0). Email of the Terraform admin SA (phase-0 human bootstrap + gcp-bootstrap APPLY identity only). Kept for backward compatibility; TFC workspaces now use tfc_plan_service_accounts / tfc_apply_service_accounts."
  value       = local.contract.terraform_admin_email
}

output "suffix" {
  description = "Deprecated: read contract.suffix (removed in v1.0). Random suffix used for globally-unique project IDs; shared with the projects stage for ID consistency."
  value       = local.contract.suffix
}

output "github_oidc_pool_id" {
  description = "Deprecated: read contract.github_oidc_pool_id (removed in v1.0). Workload Identity Pool ID for GitHub Actions OIDC."
  value       = local.contract.github_oidc_pool_id
}

output "github_oidc_pool_name" {
  description = "Deprecated: read contract.github_oidc_pool_name (removed in v1.0). Fully-qualified Workload Identity Pool name for GitHub Actions OIDC."
  value       = local.contract.github_oidc_pool_name
}

output "github_oidc_provider_name" {
  description = "Deprecated: read contract.github_oidc_provider_name (removed in v1.0). Fully-qualified WIF provider name for use in GitHub Actions (google-github-actions/auth)."
  value       = local.contract.github_oidc_provider_name
}

output "tfc_oidc_pool_id" {
  description = "Deprecated: read contract.tfc_oidc_pool_id (removed in v1.0). Workload Identity Pool ID for Terraform Cloud OIDC (null if TFC OIDC not configured)."
  value       = local.contract.tfc_oidc_pool_id
}

output "tfc_oidc_pool_name" {
  description = "Deprecated: read contract.tfc_oidc_pool_name (removed in v1.0). Fully-qualified Workload Identity Pool name for Terraform Cloud OIDC (null if not configured)."
  value       = local.contract.tfc_oidc_pool_name
}

output "tfc_oidc_provider_name" {
  description = "Deprecated: read contract.tfc_oidc_provider_name (removed in v1.0). Fully-qualified WIF provider name for Terraform Cloud OIDC (null if not configured)."
  value       = local.contract.tfc_oidc_provider_name
}

output "resman_email" {
  description = "Deprecated: read contract.resman_email (removed in v1.0). DEPRECATED — use stage_service_accounts. Email of the organization-stage apply SA."
  value       = local.contract.resman_email
}

# ── Per-stage / per-phase identities ─────────────────────────────────────────
# Consumed by envs/tfc-admin to set TFC_GCP_PLAN_SERVICE_ACCOUNT_EMAIL,
# TFC_GCP_APPLY_SERVICE_ACCOUNT_EMAIL and TFC_GCP_WORKLOAD_PROVIDER_NAME on each
# workspace. Keep these keys stable.

output "tfc_plan_service_accounts" {
  description = "Deprecated: read contract.tfc_plan_service_accounts (removed in v1.0). Map of TFC workspace name -> plan-phase (read-only) SA email."
  value       = local.contract.tfc_plan_service_accounts
}

output "tfc_apply_service_accounts" {
  description = "Deprecated: read contract.tfc_apply_service_accounts (removed in v1.0). Map of TFC workspace name -> apply-phase SA email."
  value       = local.contract.tfc_apply_service_accounts
}

output "tfc_workload_provider_name" {
  description = "Deprecated: read contract.tfc_workload_provider_name (removed in v1.0). Full TFC WIF provider resource name (projects/<number>/locations/global/workloadIdentityPools/tfc-pool/providers/terraform-cloud), for TFC_GCP_WORKLOAD_PROVIDER_NAME. Null if TFC OIDC is disabled."
  value       = local.contract.tfc_workload_provider_name
}

output "stage_service_accounts" {
  description = "Deprecated: read contract.stage_service_accounts (removed in v1.0). Map of control-plane stage -> { plan, apply } SA emails (e.g. for VPC-SC ingress identities)."
  value       = local.contract.stage_service_accounts
}

output "workload_service_accounts" {
  description = "Deprecated: read contract.workload_service_accounts (removed in v1.0). Map of environment key -> { plan, apply } SA emails. Consumed by gcp-projects (env-folder grants)."
  value       = local.contract.workload_service_accounts
}

output "workload_folder_roles" {
  description = "Deprecated: read contract.workload_folder_roles (removed in v1.0). Env-folder roles for workload SAs ({ plan, apply }); consumed by gcp-projects."
  value       = local.contract.workload_folder_roles
}

output "network_folder_roles" {
  description = "Deprecated: read contract.network_folder_roles (removed in v1.0). Shared-folder roles for the network-hub SAs ({ plan, apply }); consumed by gcp-projects."
  value       = local.contract.network_folder_roles
}

output "delegated_workload_folder_roles" {
  description = "Deprecated: read contract.delegated_workload_folder_roles (removed in v1.0). Roles projects-apply may grant on each environment folder; consumed by gcp-organization (per-folder delegated folderIamAdmin)."
  value       = local.contract.delegated_workload_folder_roles
}

output "delegated_network_folder_roles" {
  description = "Deprecated: read contract.delegated_network_folder_roles (removed in v1.0). Roles projects-apply may grant on the shared folder; consumed by gcp-organization (per-folder delegated folderIamAdmin)."
  value       = local.contract.delegated_network_folder_roles
}

output "plan_viewer_role" {
  description = "Deprecated: read contract.plan_viewer_role (removed in v1.0). Full name of the metadata-only plan viewer custom role (null when disabled)."
  value       = local.contract.plan_viewer_role
}

output "production_workspaces_bound_by_name" {
  description = "Deprecated: read contract.production_workspaces_bound_by_name (removed in v1.0). Control-plane and production workload workspaces still WIF-bound by mutable name; add their IDs to tfc_workspace_ids."
  value       = local.contract.production_workspaces_bound_by_name
}

output "guardrail_owner_mode" {
  description = "Deprecated: read contract.guardrail_owner_mode (removed in v1.0). Deny-policy ownership mode; gcp-organization defaults its guardrail_owner_mode to this."
  value       = local.contract.guardrail_owner_mode
}

output "guardrails_service_account" {
  description = "Deprecated: read contract.guardrails_service_account (removed in v1.0). Guardrails SA email (sole automation holder of roles/iam.denyAdmin), or null in organization mode."
  value       = local.contract.guardrails_service_account
}

output "guardrails_plan_service_account" {
  description = "Deprecated: read contract.guardrails_plan_service_account (removed in v1.0). Read-only plan SA of the gcp-guardrails workspace, or null in organization mode."
  value       = local.contract.guardrails_plan_service_account
}

output "guardrails_workspace_bound_by_id" {
  description = "Deprecated: read contract.guardrails_workspace_bound_by_id (removed in v1.0). Whether the gcp-guardrails workspace is WIF-bound by its immutable ID (it is never bound by name; add its ID to tfc_workspace_ids)."
  value       = local.contract.guardrails_workspace_bound_by_id
}
