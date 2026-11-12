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
#    IAM accepts at most 10 roles in one modifiedGrantsByRole hasOnly() list,
#    and Google advises against joining hasOnly() calls with && or ||. So each
#    folder's sorted list is split into chunks of 10 or fewer, with one
#    conditional binding (same member and role, its own condition) per chunk.
#    IAM evaluates each binding on its own: a request that changes the grants
#    of one role matches the chunk that lists that role. A request that changes
#    roles from two chunks at once matches no single binding and is denied.
#    gcp-projects therefore turns off the google provider's IAM batching
#    (envs/gcp/projects/providers.tf), which would otherwise merge the
#    google_folder_iam_member changes on one folder into one setIamPolicy call.
#
# 3. The workload roles that control IAM, identities, data-plane IAM or project
#    ownership on an environment folder (non_delegable_workload_folder_roles:
#    for example projectIamAdmin, serviceAccountUser, secretmanager.admin,
#    storage.admin, resourcemanager.projectCreator). An IAM condition on a delegated
#    folderIamAdmin can restrict the ROLES a grant names
#    (iam.googleapis.com/modifiedGrantsByRole) but not the MEMBERS: there is no
#    member attribute. A delegate allowed to grant projectIamAdmin could grant
#    it to itself and then grant roles/owner on every project in the folder. So
#    these roles never enter the delegated allow-list; this stage grants them to
#    the workload SAs directly.

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

  # Role allow-lists with the non-delegable roles removed. Subtracting here (not
  # only in gcp-bootstrap) keeps an older bootstrap contract, or a hand-written
  # one in config, from re-opening the self-grant path.
  effective_delegated_workload_folder_roles = sort(setsubtract(toset(var.delegated_workload_folder_roles), toset(var.non_delegable_workload_folder_roles)))
  effective_delegated_network_folder_roles  = sort(setsubtract(toset(var.delegated_network_folder_roles), toset(var.non_delegable_workload_folder_roles)))

  # Delegated folder-IAM targets: { folder key => allowed role list }.
  delegated_folder_iam_targets = var.projects_apply_service_account == null ? {} : {
    for k in keys(var.environments) : k => (
      k == var.shared_folder_key ? local.effective_delegated_network_folder_roles : local.effective_delegated_workload_folder_roles
    )
    if length(k == var.shared_folder_key ? local.effective_delegated_network_folder_roles : local.effective_delegated_workload_folder_roles) > 0
  }

  # One delegated binding per chunk of 10 roles or fewer (see 2. above):
  # { "<folder>" (chunk 0) or "<folder>|<i>" (chunk i >= 1) => chunk }. Chunk 0
  # keeps the folder key, title and description that the single binding had, so
  # a folder with 10 roles or fewer plans no change.
  delegated_folder_iam_chunks = merge([
    for k, roles in local.delegated_folder_iam_targets : {
      for i, chunk in chunklist(sort(roles), 10) : (i == 0 ? k : "${k}|${i}") => {
        folder = k
        index  = i
        count  = ceil(length(roles) / 10)
        roles  = chunk
      }
    }
  ]...)

  # Non-delegable workload roles, granted here: { "<env>|<phase>|<role>" => ... }
  # on each environment's own folder, for the roles workload_folder_roles lists.
  non_delegable_workload_grants = merge([
    for env, sas in var.workload_service_accounts : merge([
      for phase in ["plan", "apply"] : {
        for role in sort(setintersection(toset(var.workload_folder_roles[phase]), toset(var.non_delegable_workload_folder_roles))) : "${env}|${phase}|${role}" => {
          env    = env
          role   = role
          member = "serviceAccount:${sas[phase]}"
        }
      }
    ]...)
    if contains(keys(var.environments), env) && env != var.shared_folder_key
  ]...)
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
  for_each = local.delegated_folder_iam_chunks

  folder = module.organization.folders[each.value.folder].name
  role   = "roles/resourcemanager.folderIamAdmin"
  member = "serviceAccount:${var.projects_apply_service_account}"

  # The provider replaces the binding when any condition field changes, so a
  # single-chunk folder keeps the title and description it had before the split.
  condition {
    title       = each.value.index == 0 ? "delegated_folder_role_grants" : "delegated_folder_role_grants_${each.value.index}"
    description = "projects-apply may only grant the ${each.value.folder == var.shared_folder_key ? "network" : "workload"} folder roles on this folder${each.value.count > 1 ? " (part ${each.value.index + 1} of ${each.value.count})" : ""}"
    expression  = "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([${join(", ", [for r in each.value.roles : "'${r}'"])}])"
  }

  lifecycle {
    precondition {
      condition     = length(each.value.roles) >= 1 && length(each.value.roles) <= 10
      error_message = "A delegated folder-IAM condition must list 1 to 10 roles: IAM rejects a modifiedGrantsByRole hasOnly() list of more than 10 values."
    }
  }
}

# The non-delegable workload roles (see 3. above), granted by this stage so
# that projects-apply never needs them in its allow-list.
resource "google_folder_iam_member" "workload_non_delegable_folder_roles" {
  for_each = local.non_delegable_workload_grants

  folder = module.organization.folders[each.value.env].name
  role   = each.value.role
  member = each.value.member
}
