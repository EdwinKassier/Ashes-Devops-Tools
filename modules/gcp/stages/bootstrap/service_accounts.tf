# Per-stage automation identities (Cloud Foundation Fabric FAST pattern).
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
# billing account). Workload SAs get billing roles only here; their VPC-SC rights
# are granted by gcp-organization on their OWN folder-scoped access policy.
#
# Plan identities never get roles/viewer (it reads GCS objects through legacy
# bucket roles and BigQuery table data). They get metadata-only predefined
# viewers plus the org custom role below (plan_viewer.tf), which holds only
# get/list/getIamPolicy permissions.

locals {
  control_plane_stages = ["bootstrap", "organization", "projects", "network-hub"]

  # Full resource name of the org-level plan viewer custom role (plan_viewer.tf).
  # Built from the inputs (not the resource) so for_each keys stay plan-known.
  plan_viewer_role  = "organizations/${var.org_id}/roles/${var.plan_viewer_role_id}"
  plan_viewer_roles = var.enable_plan_viewer_role ? [local.plan_viewer_role] : []

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
    # iam.organizationRoleAdmin: the plan viewer custom role (plan_viewer.tf).
    "bootstrap-apply" = {
      org           = ["roles/resourcemanager.organizationViewer", "roles/iam.securityAdmin", "roles/iam.organizationRoleAdmin"]
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
        ], var.enable_scoped_access_policies ? ["roles/accesscontextmanager.policyReader"] : [],
        var.enable_pam ? ["roles/privilegedaccessmanager.viewer"] : [],
      var.enable_principal_access_boundary ? ["roles/iam.principalAccessBoundaryViewer"] : [])
      # Metadata-only viewers (no roles/viewer: no object or table-data reads).
      admin_project = concat([
        "roles/cloudkms.viewer",
        "roles/monitoring.viewer",
        "roles/pubsub.viewer",
        "roles/bigquery.metadataViewer",
        "roles/serviceusage.serviceUsageViewer",
      ], local.plan_viewer_roles)
      billing = ["roles/billing.viewer"]
    }
    # Folders + folder IAM, org IAM (org admin groups, audit configs), org
    # policies, org sinks, SCC notifications, tags, deny policies, contacts;
    # KMS / audit bucket / Pub/Sub / BigQuery / alerting in the admin project;
    # billing budgets. With enable_scoped_access_policies it also creates one
    # folder-scoped access policy per environment and grants the workload SAs
    # their rights on it (accesscontextmanager.policyAdmin); with enable_pam it
    # manages the JIT org-admin entitlement (privilegedaccessmanager.admin).
    "organization-apply" = {
      org = concat([
        "roles/resourcemanager.organizationViewer",
        "roles/resourcemanager.folderAdmin",
        "roles/iam.securityAdmin",
        "roles/orgpolicy.policyAdmin",
        "roles/logging.configWriter",
        "roles/securitycenter.notificationConfigEditor",
        "roles/resourcemanager.tagAdmin",
        "roles/resourcemanager.tagUser",
        "roles/essentialcontacts.admin",
        ], var.enable_scoped_access_policies ? ["roles/accesscontextmanager.policyAdmin"] : [],
        var.enable_pam ? ["roles/privilegedaccessmanager.admin"] : [],
        # roles/iam.denyAdmin only in the legacy single-owner mode. In the default
        # "separate" mode the deny policies (incl. the containment policy that
        # constrains THIS identity) are owned by the guardrails identity below.
        var.guardrail_owner_mode == "organization" ? ["roles/iam.denyAdmin"] : [],
      var.enable_principal_access_boundary ? ["roles/iam.principalAccessBoundaryAdmin"] : [])
      admin_project = concat([
        "roles/cloudkms.admin",
        "roles/storage.admin",
        "roles/pubsub.admin",
        "roles/bigquery.admin",
        "roles/monitoring.editor",
        "roles/logging.configWriter",
        "roles/serviceusage.serviceUsageAdmin",
        # Principal access boundary binding on the admin project
        # (resourcemanager.projects.createPolicyBinding).
      ], var.enable_principal_access_boundary ? ["roles/resourcemanager.projectIamAdmin"] : [])
      billing = ["roles/billing.costsManager"]
    }
    "projects-plan" = {
      org           = concat(local.plan_org_baseline, ["roles/serviceusage.serviceUsageViewer"])
      admin_project = ["roles/monitoring.metricsScopesViewer"]
      billing       = ["roles/billing.viewer"]
    }
    # Project creation + billing link + metrics scope. Folder IAM (to grant the
    # workload / network SAs their folder roles) is a SEPARATE, conditional
    # delegated folderIamAdmin grant made by gcp-organization on EACH target
    # folder (env folders: workload roles only; shared folder: network roles
    # only), so it cannot reach any other folder or the org node.
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
  # LEGACY (enable_legacy_org_access_policy_grants): workload SAs on the single
  # org-wide access policy. Every wl-<env>-apply could then edit EVERY perimeter
  # (prod and hub included), so it is off by default; the default model grants
  # each environment rights on its own folder-scoped policy (gcp-organization).
  access_policy_grants = var.enable_legacy_org_access_policy_grants && var.vpc_sc_access_policy_id != null ? {
    for sa_key, sa in local.workload_identities : sa_key => {
      sa_key = sa_key
      role   = sa.phase == "apply" ? "roles/accesscontextmanager.policyEditor" : "roles/accesscontextmanager.policyReader"
    }
  } : {}

  # Effective folder role lists: the plan viewer custom role is appended to the
  # workload plan roles (env folders) and the network plan roles (shared folder).
  effective_workload_folder_roles = {
    plan  = distinct(concat(var.workload_folder_roles.plan, local.plan_viewer_roles))
    apply = var.workload_folder_roles.apply
  }
  effective_network_folder_roles = {
    plan  = distinct(concat(var.network_folder_roles.plan, local.plan_viewer_roles))
    apply = var.network_folder_roles.apply
  }

  # Roles the projects-apply SA may hand out on folders (IAM delegated role
  # grants). Admin project sits directly under the org node, not in a folder, so
  # this delegation can never reach the automation project or the org node.
  delegated_workload_folder_roles = sort(distinct(concat(local.effective_workload_folder_roles.plan, local.effective_workload_folder_roles.apply)))
  delegated_network_folder_roles  = sort(distinct(concat(local.effective_network_folder_roles.plan, local.effective_network_folder_roles.apply)))
  delegated_folder_roles          = sort(distinct(concat(local.delegated_workload_folder_roles, local.delegated_network_folder_roles)))
}

resource "google_service_account" "stage" {
  for_each = local.created_identities

  project      = module.admin_project.project_id
  account_id   = each.value.account_id
  display_name = "Terraform ${each.value.kind == "workload" ? "workload ${each.value.env}" : each.value.stage} (${each.value.phase})"
  description  = "TFC ${each.value.phase}-phase identity for workspace ${each.value.workspace}. ${each.value.phase == "plan" ? "Read-only." : "Least-privilege write."} Managed by gcp-bootstrap."
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
  # checkov:skip=CKV_GCP_45:iam.securityAdmin is restricted to the bootstrap and organization APPLY identities (apply-phase WIF only); see the role matrix above.
  for_each = { for k, v in local.org_grants : k => v if v.role == "roles/iam.securityAdmin" }

  org_id = var.org_id
  role   = each.value.role #tfsec:ignore:google-iam-no-privileged-service-accounts - only the bootstrap + organization APPLY SAs (apply-phase WIF, control-plane workspaces) hold org IAM admin; no plan or workload identity does
  member = "serviceAccount:${local.stage_sa_email[each.value.sa_key]}"
}

# LEGACY (enable_org_level_folder_iam_delegation): projects-apply delegated
# folder-IAM admin bound at the ORG node. The condition limits WHICH roles it may
# grant but not WHERE: any folder in the org. The default model binds it on each
# target folder instead (gcp-organization, from the delegated_*_folder_roles
# outputs). Kept only to bridge a migration; off by default.
resource "google_organization_iam_member" "projects_delegated_folder_iam" {
  count = var.enable_org_level_folder_iam_delegation ? 1 : 0

  org_id = var.org_id
  role   = "roles/resourcemanager.folderIamAdmin"
  member = "serviceAccount:${local.stage_sa_email["projects-apply"]}"

  condition {
    title       = "delegated_folder_role_grants"
    description = "projects-apply may only grant the workload/network folder roles"
    expression  = "api.getAttribute('iam.googleapis.com/modifiedGrantsByRole', []).hasOnly([${join(", ", [for r in local.delegated_folder_roles : "'${r}'"])}])"
  }
}

resource "google_project_iam_member" "stage_admin_project_roles" {
  for_each = local.admin_project_grants

  # The plan viewer custom role must exist before it is granted.
  depends_on = [google_organization_iam_custom_role.plan_viewer]

  project = module.admin_project.project_id
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

# LEGACY: workload SAs on the org-wide access policy (see access_policy_grants).
resource "google_access_context_manager_access_policy_iam_member" "workload" {
  for_each = local.access_policy_grants

  name   = "accessPolicies/${var.vpc_sc_access_policy_id}"
  role   = each.value.role
  member = "serviceAccount:${local.stage_sa_email[each.value.sa_key]}"
}

# WIF bindings fall back to the (mutable, squattable) workspace NAME when a
# workspace has no tfc_workspace_ids entry. Tolerable while standing up a
# non-production org; once any environment is production, every control-plane
# workspace and every production workload workspace MUST be bound by its
# immutable ID. This is a hard failure (precondition), not a warning: apply the
# tfc-admin root first and feed its workspace_ids output into tfc_workspace_ids.
locals {
  name_bound_production_workspaces = sort([
    for ws in concat(
      values(var.control_plane_workspaces),
      [for env in var.production_workload_environments : "${var.tfc_workload_workspace_prefix}${env}"],
    ) : ws if !contains(keys(var.tfc_workspace_ids), ws)
  ])
}

resource "terraform_data" "production_workspaces_bound_by_id" {
  input = local.name_bound_production_workspaces

  lifecycle {
    precondition {
      condition     = !var.enable_tfc_oidc || length(var.production_workload_environments) == 0 || length(local.name_bound_production_workspaces) == 0
      error_message = "Production environments exist (${join(", ", sort(tolist(var.production_workload_environments)))}) but these workspaces would be WIF-bound by mutable NAME, not immutable ID: ${join(", ", local.name_bound_production_workspaces)}. Add their ws-... IDs to tfc_workspace_ids (tfc-admin output workspace_ids) and re-plan gcp-bootstrap."
    }
  }
}

# ─── Guardrail owner (separation of duties for IAM deny policies) ────────────
#
# The gcp-organization apply identity is the identity the admin-containment
# deny policy constrains. If it also held roles/iam.denyAdmin it could simply
# delete that policy (iam.denypolicies.* is not deny-supported, so a deny policy
# cannot protect itself). In the default "separate" mode a dedicated
# <prefix>-guardrails-apply SA is the ONLY automation identity with denyAdmin.
#
# Routine path: the security-team gcp-guardrails workspace (envs/gcp/guardrails,
# its own HCP project, security team only) plans as <prefix>-guardrails-plan
# and applies as <prefix>-guardrails-apply. Both are WIF-bound to that
# workspace by its immutable ID ONLY, never by its squattable name: without a
# tfc_workspace_ids entry there is no binding at all (and a production estate
# fails the plan).
#
# Break-glass path: guardrail_owner_members (a PAM-gated group, ideally)
# impersonate the apply SA and apply the deny_policy_specs output of
# gcp-guardrails by hand (docs/runbooks/break-glass.md). Residual:
# iam.securityAdmin on the organization apply SA could still grant itself
# denyAdmin; the control-plane watch "guardrail_role_grant" alerts on exactly
# that grant.
locals {
  guardrails_separate = var.guardrail_owner_mode == "separate"
  # The workspace identity exists whenever a guardrails workspace is declared;
  # its WIF binding additionally needs TFC OIDC and the workspace ID.
  guardrails_workspace_identity = local.guardrails_separate && var.guardrails_workspace != null
  guardrails_wif_wanted         = local.guardrails_workspace_identity && var.enable_tfc_oidc && var.tfc_organization != null
  guardrails_workspace_id       = local.guardrails_workspace_identity ? lookup(var.tfc_workspace_ids, var.guardrails_workspace, null) : null
  guardrails_wif_bound          = local.guardrails_wif_wanted && local.guardrails_workspace_id != null

  guardrails_tfc_bindings = local.guardrails_wif_bound ? [
    {
      workspace_name        = var.guardrails_workspace
      workspace_id          = local.guardrails_workspace_id
      run_phase             = "plan"
      service_account_email = google_service_account.guardrails_plan[0].email
    },
    {
      workspace_name        = var.guardrails_workspace
      workspace_id          = local.guardrails_workspace_id
      run_phase             = "apply"
      service_account_email = google_service_account.guardrails[0].email
    },
  ] : []
}

resource "google_service_account" "guardrails" {
  count = local.guardrails_separate ? 1 : 0

  project      = module.admin_project.project_id
  account_id   = "${var.project_prefix}-guardrails-apply"
  display_name = "Terraform guardrail owner (deny policies)"
  description  = "Sole automation holder of roles/iam.denyAdmin. Applies the org deny policies from the gcp-guardrails workspace; break-glass impersonation only by guardrail_owner_members. Managed by gcp-bootstrap."
}

# resourcemanager.tagViewer: gcp-guardrails looks up the containment tag.
resource "google_organization_iam_member" "guardrails" {
  for_each = local.guardrails_separate ? toset(["roles/iam.denyAdmin", "roles/resourcemanager.organizationViewer", "roles/resourcemanager.tagViewer"]) : toset([])

  org_id = var.org_id
  role   = each.value
  member = "serviceAccount:${google_service_account.guardrails[0].email}"
}

resource "google_service_account_iam_member" "guardrails_impersonation" {
  for_each = local.guardrails_separate ? toset(var.guardrail_owner_members) : toset([])

  service_account_id = google_service_account.guardrails[0].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = each.value
}

# Read-only plan identity of the gcp-guardrails workspace.
resource "google_service_account" "guardrails_plan" {
  count = local.guardrails_workspace_identity ? 1 : 0

  project      = module.admin_project.project_id
  account_id   = "${var.project_prefix}-guardrails-plan"
  display_name = "Terraform guardrails plan (read-only)"
  description  = "Plan-phase identity of the gcp-guardrails workspace: reads deny policies and tags, changes nothing. Managed by gcp-bootstrap."
}

resource "google_organization_iam_member" "guardrails_plan" {
  for_each = local.guardrails_workspace_identity ? toset(["roles/iam.denyReviewer", "roles/resourcemanager.organizationViewer", "roles/resourcemanager.tagViewer"]) : toset([])

  org_id = var.org_id
  role   = each.value
  member = "serviceAccount:${google_service_account.guardrails_plan[0].email}"
}

# By ID only: a production estate fails the plan until tfc_workspace_ids holds
# the gcp-guardrails ID (tfc-admin writes it onto gcp-bootstrap; output
# gcp_bootstrap_tfvars for the local phase-0 apply). Outside production the
# workspace simply cannot authenticate until then (output
# guardrails_workspace_bound_by_id = false); it is never bound by name.
resource "terraform_data" "guardrails_workspace_bound_by_id" {
  input = local.guardrails_workspace_id

  lifecycle {
    precondition {
      condition     = !local.guardrails_wif_wanted || local.guardrails_workspace_id != null || length(var.production_workload_environments) == 0
      error_message = "Production environments exist but tfc_workspace_ids has no entry for ${coalesce(var.guardrails_workspace, "the guardrails workspace")}: its WIF binding is by immutable workspace ID only, so the security-team guardrails workspace could not authenticate. Add its ws-... ID (tfc-admin output workspace_ids) to tfc_workspace_ids and re-plan gcp-bootstrap, or set guardrails_workspace = null to keep only the PAM break-glass path."
    }
  }
}
