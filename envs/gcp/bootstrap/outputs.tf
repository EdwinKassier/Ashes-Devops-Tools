# Cross-root contract (Convention 4). Consumed by gcp-organization (and future
# gcp control-plane roots) via terraform_remote_state. Keep these keys stable
# across refactors — renaming one breaks the downstream root at plan.

output "admin_project_id" {
  description = "The admin (seed) project ID that hosts the Terraform admin SA and WIF pools."
  value       = module.bootstrap.admin_project_id
}

output "admin_project_number" {
  description = "The admin project number, used by WIF pool references and VPC-SC ingress policies."
  value       = module.bootstrap.admin_project_number
}

output "terraform_admin_email" {
  description = "Email of the Terraform admin SA (phase-0 human bootstrap + gcp-bootstrap APPLY identity only). Kept for backward compatibility; TFC workspaces now use tfc_plan_service_accounts / tfc_apply_service_accounts."
  value       = module.bootstrap.terraform_admin_email
}

output "suffix" {
  description = "Random suffix used for globally-unique project IDs; shared with the projects stage for ID consistency."
  value       = module.bootstrap.suffix
}

output "github_oidc_pool_id" {
  description = "Workload Identity Pool ID for GitHub Actions OIDC."
  value       = module.bootstrap.github_oidc_pool_id
}

output "github_oidc_pool_name" {
  description = "Fully-qualified Workload Identity Pool name for GitHub Actions OIDC."
  value       = module.bootstrap.github_oidc_pool_name
}

output "github_oidc_provider_name" {
  description = "Fully-qualified WIF provider name for use in GitHub Actions (google-github-actions/auth)."
  value       = module.bootstrap.github_oidc_provider_name
}

output "tfc_oidc_pool_id" {
  description = "Workload Identity Pool ID for Terraform Cloud OIDC (null if TFC OIDC not configured)."
  value       = module.bootstrap.tfc_oidc_pool_id
}

output "tfc_oidc_pool_name" {
  description = "Fully-qualified Workload Identity Pool name for Terraform Cloud OIDC (null if not configured)."
  value       = module.bootstrap.tfc_oidc_pool_name
}

output "tfc_oidc_provider_name" {
  description = "Fully-qualified WIF provider name for Terraform Cloud OIDC (null if not configured)."
  value       = module.bootstrap.tfc_oidc_provider_name
}

output "resman_email" {
  description = "DEPRECATED — use stage_service_accounts. Email of the organization-stage apply SA."
  value       = module.bootstrap.resman_email
}

# ── Per-stage / per-phase identities ─────────────────────────────────────────
# Consumed by envs/tfc-admin to set TFC_GCP_PLAN_SERVICE_ACCOUNT_EMAIL,
# TFC_GCP_APPLY_SERVICE_ACCOUNT_EMAIL and TFC_GCP_WORKLOAD_PROVIDER_NAME on each
# workspace. Keep these keys stable.

output "tfc_plan_service_accounts" {
  description = "Map of TFC workspace name -> plan-phase (read-only) SA email."
  value       = module.bootstrap.tfc_plan_service_accounts
}

output "tfc_apply_service_accounts" {
  description = "Map of TFC workspace name -> apply-phase SA email."
  value       = module.bootstrap.tfc_apply_service_accounts
}

output "tfc_workload_provider_name" {
  description = "Full TFC WIF provider resource name (projects/<number>/locations/global/workloadIdentityPools/tfc-pool/providers/terraform-cloud), for TFC_GCP_WORKLOAD_PROVIDER_NAME. Null if TFC OIDC is disabled."
  value       = module.bootstrap.tfc_workload_provider_name
}

output "stage_service_accounts" {
  description = "Map of control-plane stage -> { plan, apply } SA emails (e.g. for VPC-SC ingress identities)."
  value       = module.bootstrap.stage_service_accounts
}

output "workload_service_accounts" {
  description = "Map of environment key -> { plan, apply } SA emails. Consumed by gcp-projects (env-folder grants)."
  value       = module.bootstrap.workload_service_accounts
}

output "workload_folder_roles" {
  description = "Env-folder roles for workload SAs ({ plan, apply }); consumed by gcp-projects."
  value       = module.bootstrap.workload_folder_roles
}

output "network_folder_roles" {
  description = "Shared-folder roles for the network-hub SAs ({ plan, apply }); consumed by gcp-projects."
  value       = module.bootstrap.network_folder_roles
}

output "delegated_workload_folder_roles" {
  description = "Roles projects-apply may grant on each environment folder; consumed by gcp-organization (per-folder delegated folderIamAdmin)."
  value       = module.bootstrap.delegated_workload_folder_roles
}

output "delegated_network_folder_roles" {
  description = "Roles projects-apply may grant on the shared folder; consumed by gcp-organization (per-folder delegated folderIamAdmin)."
  value       = module.bootstrap.delegated_network_folder_roles
}

output "plan_viewer_role" {
  description = "Full name of the metadata-only plan viewer custom role (null when disabled)."
  value       = module.bootstrap.plan_viewer_role
}

output "production_workspaces_bound_by_name" {
  description = "Control-plane and production workload workspaces still WIF-bound by mutable name; add their IDs to tfc_workspace_ids."
  value       = module.bootstrap.production_workspaces_bound_by_name
}

output "guardrail_owner_mode" {
  description = "Deny-policy ownership mode; gcp-organization defaults its guardrail_owner_mode to this."
  value       = module.bootstrap.guardrail_owner_mode
}

output "guardrails_service_account" {
  description = "Guardrails SA email (sole automation holder of roles/iam.denyAdmin), or null in organization mode."
  value       = module.bootstrap.guardrails_service_account
}
