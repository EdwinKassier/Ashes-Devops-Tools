output "admin_project_id" {
  description = "Project ID of the admin project"
  value       = module.admin_project.project_id
}

output "admin_project_number" {
  description = "Project Number of the admin project"
  value       = module.admin_project.number
}

output "terraform_admin_email" {
  description = "Email of the Terraform Admin Service Account"
  value       = module.terraform_admin_sa.email
}

output "suffix" {
  description = "Random suffix used for uniqueness"
  value       = random_id.suffix.hex
}

output "github_oidc_pool_id" {
  description = "Workload Identity Pool ID for GitHub Actions OIDC (null unless enable_github_wif = true)"
  value       = var.enable_github_wif ? module.gh_oidc[0].pool_id : null
}

output "github_oidc_pool_name" {
  description = "Fully-qualified Workload Identity Pool name for GitHub Actions OIDC (null unless enable_github_wif = true)"
  value       = var.enable_github_wif ? module.gh_oidc[0].pool_name : null
}

output "github_oidc_provider_name" {
  description = "Fully-qualified Workload Identity Provider name for GitHub Actions (null unless enable_github_wif = true)"
  value       = var.enable_github_wif ? module.gh_oidc[0].github_provider_name : null
}

output "tfc_oidc_pool_id" {
  description = "Workload Identity Pool ID for Terraform Cloud OIDC (null if TFC OIDC not enabled)"
  value       = length(module.tfc_oidc) > 0 ? module.tfc_oidc[0].pool_id : null
}

output "tfc_oidc_pool_name" {
  description = "Fully-qualified Workload Identity Pool name for Terraform Cloud OIDC (null if TFC OIDC not enabled)"
  value       = length(module.tfc_oidc) > 0 ? module.tfc_oidc[0].pool_name : null
}

output "tfc_oidc_provider_name" {
  description = "Fully-qualified Workload Identity Provider name for Terraform Cloud OIDC (null if TFC OIDC not enabled)"
  value       = length(module.tfc_oidc) > 0 ? module.tfc_oidc[0].tfc_provider_name : null
}

output "tfc_workload_provider_name" {
  description = "Full WIF provider resource name (projects/<number>/locations/global/workloadIdentityPools/tfc-pool/providers/terraform-cloud) for the TFC_GCP_WORKLOAD_PROVIDER_NAME workspace variable. Null if TFC OIDC not enabled."
  value       = length(module.tfc_oidc) > 0 ? module.tfc_oidc[0].tfc_provider_name : null
}

output "tfc_attribute_condition" {
  description = "The CEL attribute_condition on the TFC WIF provider (null if TFC OIDC not enabled)."
  value       = length(module.tfc_oidc) > 0 ? module.tfc_oidc[0].tfc_attribute_condition : null
}

output "tfc_plan_service_accounts" {
  description = "Map of TFC workspace name -> PLAN-phase SA email (set as TFC_GCP_PLAN_SERVICE_ACCOUNT_EMAIL on that workspace)."
  value       = { for k, sa in local.tfc_identities : sa.workspace => local.stage_sa_email[k] if sa.phase == "plan" }
}

output "tfc_apply_service_accounts" {
  description = "Map of TFC workspace name -> APPLY-phase SA email (set as TFC_GCP_APPLY_SERVICE_ACCOUNT_EMAIL on that workspace)."
  value       = { for k, sa in local.tfc_identities : sa.workspace => local.stage_sa_email[k] if sa.phase == "apply" }
}

output "stage_service_accounts" {
  description = "Map of control-plane stage (bootstrap, organization, projects, network-hub) -> { plan, apply } SA emails."
  value = {
    for stage in local.control_plane_stages : stage => {
      plan  = local.stage_sa_email["${stage}-plan"]
      apply = local.stage_sa_email["${stage}-apply"]
    }
  }
}

output "workload_service_accounts" {
  description = "Map of application environment key -> { plan, apply } SA emails. Consumed by gcp-projects, which grants them roles on the environment folder."
  value = {
    for env in var.workload_environments : env => {
      plan  = local.stage_sa_email["wl-${env}-plan"]
      apply = local.stage_sa_email["wl-${env}-apply"]
    }
  }
}

output "workload_folder_roles" {
  description = "Effective folder roles for workload SAs ({ plan, apply }, plan includes the plan viewer custom role); consumed by gcp-projects so the grant list and the projects-apply delegation condition stay in lock-step."
  value       = local.effective_workload_folder_roles
}

output "network_folder_roles" {
  description = "Effective folder roles for the network-hub SAs on the shared folder ({ plan, apply }, plan includes the plan viewer custom role); consumed by gcp-projects."
  value       = local.effective_network_folder_roles
}

output "delegated_workload_folder_roles" {
  description = "Roles projects-apply may grant on each ENVIRONMENT folder. gcp-organization binds the conditional folderIamAdmin on every environment folder with this allow-list."
  value       = local.delegated_workload_folder_roles
}

output "delegated_network_folder_roles" {
  description = "Roles projects-apply may grant on the SHARED (network) folder. gcp-organization binds the conditional folderIamAdmin on the shared folder with this allow-list."
  value       = local.delegated_network_folder_roles
}

output "plan_viewer_role" {
  description = "Full name (organizations/<org>/roles/<id>) of the metadata-only plan viewer custom role, or null when enable_plan_viewer_role = false."
  value       = var.enable_plan_viewer_role ? google_organization_iam_custom_role.plan_viewer[0].name : null
}

output "production_workspaces_bound_by_name" {
  description = "Control-plane and production workload workspaces still WIF-bound by mutable name (empty when production_workload_environments is empty or every one has a tfc_workspace_ids entry)."
  value       = length(var.production_workload_environments) == 0 ? [] : local.name_bound_production_workspaces
}

output "resman_email" {
  description = "DEPRECATED (superseded by stage_service_accounts). Email of the organization-stage APPLY SA, which now holds the privileged org roles the old opt-in resman SA held."
  value       = local.stage_sa_email["organization-apply"]
}

output "org_role_grants" {
  description = "Audit view of every ORG-level role granted by this stage, keyed by identity (<stage>-<phase>). Workload identities never appear here."
  value = {
    for sa_key in distinct([for g in values(local.org_grants) : g.sa_key]) : sa_key => sort(concat(
      [for g in values(local.org_grants) : g.role if g.sa_key == sa_key],
      sa_key == "projects-apply" && var.enable_org_level_folder_iam_delegation ? ["roles/resourcemanager.folderIamAdmin"] : [],
    ))
  }
}
