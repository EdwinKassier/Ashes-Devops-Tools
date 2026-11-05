# Per-stage automation identities (audit C2 — Cloud Foundation Fabric FAST pattern).
#
# Before: ONE org-level security-admin SA (terraform-admin) was WIF-bound to every
# TFC workspace — control plane AND every gcp-workload-<env> — in BOTH run phases.
# A speculative PR plan in any workload workspace could mint an org security-admin
# token.
#
# After: each control-plane stage has a read-only PLAN SA and a least-privilege
# APPLY SA; each application environment has its own plan/apply pair holding NO
# org-level role (its rights are granted on its own env folder by the gcp-projects
# stage, see modules/gcp/stages/projects). The gcp-bootstrap apply identity stays
# the existing terraform-admin SA (it must manage org IAM for all the others).
#
# Role matrix (org = organization node, admin = admin/seed project, billing =
# billing account). Workload SAs get billing + optional access-policy roles only.

locals {
  control_plane_stages = ["bootstrap", "organization", "projects", "network-hub"]

  # Read-only baseline every control-plane plan SA gets at the org node.
  plan_org_baseline = [
    "roles/browser",
    "roles/resourcemanager.organizationViewer",
    "roles/iam.securityReviewer",
  ]

  stage_roles = {
    "bootstrap-plan" = {
      org           = local.plan_org_baseline
      admin_project = ["roles/iam.serviceAccountViewer", "roles/iam.workloadIdentityPoolViewer", "roles/serviceusage.serviceUsageViewer"]
      billing       = ["roles/billing.viewer"]
    }
    # bootstrap-apply = terraform-admin SA. iam.securityAdmin is required to
    # manage the org/billing/admin-project IAM of every other stage SA.
    "bootstrap-apply" = {
      org           = ["roles/resourcemanager.organizationViewer", "roles/iam.securityAdmin"]
      admin_project = ["roles/iam.serviceAccountAdmin", "roles/iam.workloadIdentityPoolAdmin", "roles/serviceusage.serviceUsageAdmin"]
      billing       = []
    }
    "organization-plan" = {
      org = concat(local.plan_org_baseline, [
        "roles/orgpolicy.policyViewer",
        "roles/logging.viewer",
        "roles/securitycenter.notificationConfigViewer",
        "roles/resourcemanager.tagViewer",
        "roles/iam.denyReviewer",
        "roles/essentialcontacts.viewer",
      ])
      admin_project = ["roles/viewer"]
      billing       = ["roles/billing.viewer"]
    }
    # Folders + folder IAM, org IAM (org admin groups, audit configs), org
    # policies, org sinks, SCC notifications, tags, deny policies, contacts;
    # KMS / audit bucket / Pub/Sub / BigQuery / alerting in the admin project;
    # billing budgets.
    "organization-apply" = {
      org = [
        "roles/resourcemanager.organizationViewer",
        "roles/resourcemanager.folderAdmin",
        "roles/iam.securityAdmin",
        "roles/orgpolicy.policyAdmin",
        "roles/logging.configWriter",
        "roles/securitycenter.notificationConfigEditor",
        "roles/resourcemanager.tagAdmin",
        "roles/resourcemanager.tagUser",
        "roles/iam.denyAdmin",
        "roles/essentialcontacts.admin",
      ]
      admin_project = [
        "roles/cloudkms.admin",
        "roles/storage.admin",
        "roles/pubsub.admin",
        "roles/bigquery.admin",
        "roles/monitoring.editor",
        "roles/logging.configWriter",
        "roles/serviceusage.serviceUsageAdmin",
      ]
      billing = ["roles/billing.costsManager"]
    }
    "projects-plan" = {
      org           = concat(local.plan_org_baseline, ["roles/serviceusage.serviceUsageViewer"])
      admin_project = ["roles/monitoring.metricsScopesViewer"]
      billing       = ["roles/billing.viewer"]
    }
    # Project creation + billing link + metrics scope. Folder IAM (to grant the
    # workload / network SAs their folder roles) is a SEPARATE, conditional
    # delegated grant below — it can only ever hand out the role list in
    # local.delegated_folder_roles.
    "projects-apply" = {
      org = [
        "roles/browser",
        "roles/resourcemanager.organizationViewer",
        "roles/resourcemanager.projectCreator",
        "roles/billing.projectManager",
      ]
      admin_project = ["roles/monitoring.metricsScopesAdmin"]
      billing       = ["roles/billing.user"]
    }
    "network-hub-plan" = {
      org           = concat(local.plan_org_baseline, ["roles/accesscontextmanager.policyReader"])
      admin_project = []
      billing       = []
    }
    # VPC-SC at the org access policy. Everything else (VPCs, Shared VPC host,
    # hierarchical firewall, DNS, PSA) is granted on the `shared` folder by the
    # gcp-projects stage (var.network_folder_roles).
    "network-hub-apply" = {
      org           = ["roles/browser", "roles/accesscontextmanager.policyAdmin"]
      admin_project = []
      billing       = []
    }
  }

  # ── Service accounts to create (bootstrap-apply is the existing admin SA) ──
  control_plane_identities = merge([
    for stage in local.control_plane_stages : {
      for phase in ["plan", "apply"] : "${stage}-${phase}" => {
        stage      = stage
        phase      = phase
        kind       = "control-plane"
        workspace  = var.control_plane_workspaces[stage]
        account_id = "${var.project_prefix}-${stage}-${phase}"
      }
    }
  ]...)

  workload_identities = merge([
    for env in sort(tolist(var.workload_environments)) : {
      for phase in ["plan", "apply"] : "wl-${env}-${phase}" => {
        stage      = "workload"
        env        = env
        phase      = phase
        kind       = "workload"
        workspace  = "${var.tfc_workload_workspace_prefix}${env}"
        account_id = "${var.project_prefix}-wl-${env}-${phase}"
      }
    }
  ]...)

  tfc_identities = merge(local.control_plane_identities, local.workload_identities)

  created_identities = { for k, v in local.tfc_identities : k => v if k != "bootstrap-apply" }

  stage_sa_email = merge(
    { for k, sa in google_service_account.stage : k => sa.email },
    { "bootstrap-apply" = module.terraform_admin_sa.email },
  )

  # ── Flattened grants (static for_each keys "<sa-key>|<role>") ──────────────
  org_grants = merge([
    for sa_key, roles in local.stage_roles : {
      for role in roles.org : "${sa_key}|${role}" => { sa_key = sa_key, role = role }
    }
  ]...)
  admin_project_grants = merge([
    for sa_key, roles in local.stage_roles : {
      for role in roles.admin_project : "${sa_key}|${role}" => { sa_key = sa_key, role = role }
    }
  ]...)
  billing_grants = merge(
    merge([
      for sa_key, roles in local.stage_roles : {
        for role in roles.billing : "${sa_key}|${role}" => { sa_key = sa_key, role = role }
      }
    ]...),
    merge([
      for sa_key, sa in local.workload_identities : {
        for role in var.workload_billing_roles[sa.phase] : "${sa_key}|${role}" => { sa_key = sa_key, role = role }
      }
    ]...),
  )
  access_policy_grants = var.vpc_sc_access_policy_id == null ? {} : {
    for sa_key, sa in local.workload_identities : sa_key => {
      sa_key = sa_key
      role   = sa.phase == "apply" ? "roles/accesscontextmanager.policyEditor" : "roles/accesscontextmanager.policyReader"
    }
  }

  # Roles the projects-apply SA may hand out on folders (IAM delegated role
  # grants). Admin project sits directly under the org node, not in a folder, so
  # this delegation can never reach the automation project or the org node.
  delegated_folder_roles = sort(distinct(concat(
    var.workload_folder_roles.plan,
    var.workload_folder_roles.apply,
    var.network_folder_roles.plan,
    var.network_folder_roles.apply,
  )))
}

resource "google_service_account" "stage" {
  for_each = local.created_identities

  project      = google_project.admin_project.project_id
  account_id   = each.value.account_id
  display_name = "Terraform ${each.value.kind == "workload" ? "workload ${each.value.env}" : each.value.stage} (${each.value.phase})"
  description  = "TFC ${each.value.phase}-phase identity for workspace ${each.value.workspace}. ${each.value.phase == "plan" ? "Read-only." : "Least-privilege write."} Managed by gcp-bootstrap (audit C2)."
}

# Org-level roles. Workload SAs are deliberately absent from local.stage_roles,
# so they never receive an org-level binding.
resource "google_organization_iam_member" "stage_org_roles" {
  for_each = { for k, v in local.org_grants : k => v if v.role != "roles/iam.securityAdmin" }

  org_id = var.org_id
  role   = each.value.role
  member = "serviceAccount:${local.stage_sa_email[each.value.sa_key]}"
}

# iam.securityAdmin is held by exactly two identities: the gcp-bootstrap apply
# SA (it manages every other stage SA's IAM) and the gcp-organization apply SA
# (org IAM, org audit configs, folder IAM). Neither is reachable from a plan
# phase or from any workload workspace.
resource "google_organization_iam_member" "stage_org_security_admin" {
  # checkov:skip=CKV_GCP_45:iam.securityAdmin is restricted to the bootstrap and organization APPLY identities (apply-phase WIF only); see the C2 role matrix above.
  for_each = { for k, v in local.org_grants : k => v if v.role == "roles/iam.securityAdmin" }

  org_id = var.org_id
  role   = each.value.role #tfsec:ignore:google-iam-no-privileged-service-accounts - only the bootstrap + organization APPLY SAs (apply-phase WIF, control-plane workspaces) hold org IAM admin; no plan or workload identity does
  member = "serviceAccount:${local.stage_sa_email[each.value.sa_key]}"
}

# projects-apply: delegated folder-IAM admin. The condition restricts which roles
# it may add/remove on folder IAM policies to the workload/network folder role
# lists, so it cannot grant itself (or anyone) roles/owner or org-level power.
resource "google_organization_iam_member" "projects_delegated_folder_iam" {
  org_id = var.org_id
  role   = "roles/resourcemanager.folderIamAdmin"
  member = "serviceAccount:${local.stage_sa_email["projects-apply"]}"

  condition {
    title       = "delegated_folder_role_grants"
    description = "projects-apply may only grant the workload/network folder roles (audit C2)"
    expression  = "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([${join(", ", [for r in local.delegated_folder_roles : "'${r}'"])}])"
  }
}

resource "google_project_iam_member" "stage_admin_project_roles" {
  for_each = local.admin_project_grants

  project = google_project.admin_project.project_id
  role    = each.value.role
  member  = "serviceAccount:${local.stage_sa_email[each.value.sa_key]}"
}

resource "google_billing_account_iam_member" "stage_billing_roles" {
  # checkov:skip=CKV_GCP_89:billing roles are scoped to the single landing-zone billing account and to the stage that needs them (costsManager for budgets, user for project billing links, viewer for plans).
  for_each = local.billing_grants

  billing_account_id = var.billing_account
  role               = each.value.role
  member             = "serviceAccount:${local.stage_sa_email[each.value.sa_key]}"
}

# Optional: workload environments that manage their own VPC-SC perimeter get
# policy-scoped (not org-scoped) Access Context Manager rights.
resource "google_access_context_manager_access_policy_iam_member" "workload" {
  for_each = local.access_policy_grants

  name   = "accessPolicies/${var.vpc_sc_access_policy_id}"
  role   = each.value.role
  member = "serviceAccount:${local.stage_sa_email[each.value.sa_key]}"
}
