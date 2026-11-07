# Project Creation Facade
# Creates all environment projects based on the variable definition

locals {
  project_labels = {
    managed-by = "terraform"
    owner      = "platform-team"
    # GCP label values allow only lowercase letters, digits, '_' and '-' (max
    # 63): "My Organization" becomes "my-organization". Already-valid names are
    # unchanged, so existing labels do not churn.
    organization = substr(replace(lower(var.organization_name), "/[^a-z0-9_-]/", "-"), 0, 63)
  }
}

locals {
  # Naming scheme lives HERE (the stage), not in the project primitive.
  projects = {
    for pair in flatten([
      for ou_k, ou in var.environments : [
        for proj_k, proj in ou.projects : {
          key  = "${ou_k}-${proj_k}"
          ou   = ou_k
          proj = proj
        }
      ]
    ]) : pair.key => pair
  }
}

module "project" {
  source   = "../../project"
  for_each = local.projects

  # Display names must be 4-30 chars (provider-validated). The root's built-in
  # shared projects are named "hub"/"dns" (3 chars), which failed every plan, so
  # short names are prefixed with their environment key ("shared-hub"). Names
  # that were already valid are unchanged (no churn). project_id is unaffected.
  name = length(each.value.proj.name) < 4 ? "${each.value.ou}-${each.value.proj.name}" : each.value.proj.name
  # Prevent redundant "<env>-host-<env>" naming. Use explicit names when needed.
  # Use the shared suffix to ensure ID stability
  project_id      = "${var.project_prefix}-${each.value.ou}-${each.value.proj.name}-${var.suffix}"
  billing_account = coalesce(each.value.proj.billing_account, var.default_billing_account)
  parent          = var.folders[each.value.ou].id

  labels = merge(
    local.project_labels,
    each.value.proj.labels,
    {
      environment = each.value.ou
    }
  )

  # Baseline APIs on every project, plus any per-project additions (for
  # example networkconnectivity.googleapis.com on the hub and host projects
  # when Network Connectivity Center is in use).
  services = distinct(concat(var.project_services, lookup(var.additional_project_services, each.key, [])))

  # Foundation projects must not be deletable by a routine plan.
  deletion_policy = "PREVENT"
}

# Monitoring for projects (Metrics Scope).
# The google_monitoring_monitored_project resource `name` field must be in the
# format "locations/global/metricsScopes/<scope_project_id>/projects/<monitored_project_id>".
# The GCP provider >= 4.x accepts project IDs (not just project numbers) in this path.
resource "google_monitoring_monitored_project" "projects" {
  for_each = module.project

  metrics_scope = "locations/global/metricsScopes/${var.admin_project_id}"
  # module.project[*].project_id already waits for the project's APIs.
  name = "locations/global/metricsScopes/${var.admin_project_id}/projects/${each.value.project_id}"
}

# ─── Automation identity grants ──────────────────────────────────
# The per-environment workload SAs created by gcp-bootstrap hold NO org-level
# role. Their rights live here, scoped to their OWN environment folder (FAST
# stage-3 pattern): the apply SA gets the write roles, the plan SA read-only
# roles. The network-hub SAs likewise get their network roles on the `shared`
# folder only. These grants are made by the projects-apply SA through a
# conditional (delegated) folderIamAdmin grant that only admits these role lists.

locals {
  workload_folder_grants = merge([
    for env, sas in var.workload_service_accounts : merge([
      for phase in ["plan", "apply"] : {
        for role in var.workload_folder_roles[phase] : "${env}|${phase}|${role}" => {
          folder = var.folders[env].id
          role   = role
          member = "serviceAccount:${sas[phase]}"
        }
      }
    ]...)
  ]...)

  network_folder_grants = var.network_service_accounts == null ? {} : merge([
    for phase in ["plan", "apply"] : {
      for role in var.network_folder_roles[phase] : "${phase}|${role}" => {
        folder = var.folders[var.network_folder_key].id
        role   = role
        member = "serviceAccount:${var.network_service_accounts[phase]}"
      }
    }
  ]...)
}

resource "google_folder_iam_member" "workload_sa_folder_roles" {
  # checkov:skip=CKV_GCP_44:the workload apply SA needs iam.serviceAccountUser to attach runtime SAs to its own resources; the grant is scoped to its own environment folder only.
  for_each = local.workload_folder_grants

  folder = each.value.folder
  role   = each.value.role
  member = each.value.member
}

resource "google_folder_iam_member" "network_sa_folder_roles" {
  for_each = local.network_folder_grants

  folder = each.value.folder
  role   = each.value.role
  member = each.value.member
}
