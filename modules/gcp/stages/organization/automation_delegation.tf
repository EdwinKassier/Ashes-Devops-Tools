# Automation-identity rights that need the folders, so they live here and not in
# gcp-bootstrap (which runs before any folder exists).
#
# 1. Per-environment SCOPED access policies (VPC Service Controls). A scoped
#    policy is bound to exactly one folder, and perimeters in it can only hold
#    projects under that folder. Each environment's workload SAs get rights on
#    their OWN policy only (apply: policyEditor, plan: policyReader), so a dev
#    workload can no longer edit a prod or hub perimeter in the org-wide policy.
#
# 2. projects-apply delegated folder-IAM admin, bound on EACH target folder
#    instead of the org node: environment folders admit only the workload role
#    list, the shared folder only the network role list. It cannot grant on any
#    other folder, on the admin project (directly under the org) or on the org.

locals {
  # Environment folders get a scoped policy; the shared (hub/DNS) folder stays in
  # the org-wide policy managed by gcp-network-hub.
  scoped_policy_environment_keys = var.gcp.enable_scoped_access_policies ? sort([
    for k in keys(var.environments) : k if k != var.shared_folder_key
  ]) : []

  scoped_policy_grants = merge([
    for env in local.scoped_policy_environment_keys : {
      for phase in ["plan", "apply"] : "${env}|${phase}" => {
        env    = env
        role   = phase == "apply" ? "roles/accesscontextmanager.policyEditor" : "roles/accesscontextmanager.policyReader"
        member = "serviceAccount:${var.workload_service_accounts[env][phase]}"
      }
    } if contains(keys(var.workload_service_accounts), env)
  ]...)

  # Delegated folder-IAM targets: { folder key => allowed role list }.
  delegated_folder_iam_targets = var.projects_apply_service_account == null ? {} : {
    for k in keys(var.environments) : k => (
      k == var.shared_folder_key ? var.delegated_network_folder_roles : var.delegated_workload_folder_roles
    )
    if length(k == var.shared_folder_key ? var.delegated_network_folder_roles : var.delegated_workload_folder_roles) > 0
  }
}

resource "google_access_context_manager_access_policy" "environment" {
  for_each = toset(local.scoped_policy_environment_keys)

  parent = "organizations/${var.org_id}"
  title  = "${var.project_prefix}-${each.key}-scoped"
  scopes = [module.organization.folders[each.key].name]
}

resource "google_access_context_manager_access_policy_iam_member" "environment" {
  for_each = local.scoped_policy_grants

  name   = "accessPolicies/${google_access_context_manager_access_policy.environment[each.value.env].name}"
  role   = each.value.role
  member = each.value.member
}

resource "google_folder_iam_member" "projects_delegated_folder_iam" {
  for_each = local.delegated_folder_iam_targets

  folder = module.organization.folders[each.key].name
  role   = "roles/resourcemanager.folderIamAdmin"
  member = "serviceAccount:${var.projects_apply_service_account}"

  condition {
    title       = "delegated_folder_role_grants"
    description = "projects-apply may only grant the ${each.key == var.shared_folder_key ? "network" : "workload"} folder roles on this folder"
    expression  = "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([${join(", ", [for r in sort(each.value) : "'${r}'"])}])"
  }
}
