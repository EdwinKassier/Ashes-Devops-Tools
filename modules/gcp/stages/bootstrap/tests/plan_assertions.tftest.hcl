# Plan assertions for the bootstrap stage identity model.
#
# * The shared terraform-admin SA keeps ONLY what the gcp-bootstrap apply needs
#   (org IAM admin + org viewer); the old org-wide orgpolicy/ACM/logging/SCC/xpn/
#   tag admin grants are gone from it.
# * Each control-plane stage has a read-only plan SA and a least-privilege apply SA.
# * Workload SAs hold NO org-level IAM binding.
# * Plan SAs hold no admin/editor/owner/creator/user role anywhere.
# * TFC bindings are per (workspace, run phase); the provider condition pins the org.
#
# override_module pins the terraform_admin_sa email so member strings are known
# at plan time. All runs use mock_provider — no GCP credentials required.

mock_provider "google" {}
mock_provider "random" {}

override_module {
  target = module.terraform_admin_sa
  outputs = {
    email                 = "terraform-admin@mock-org-admin-abcd1234.iam.gserviceaccount.com"
    name                  = "projects/mock-org-admin-abcd1234/serviceAccounts/terraform-admin@mock-org-admin-abcd1234.iam.gserviceaccount.com"
    unique_id             = "123456789012345678901"
    member                = "serviceAccount:terraform-admin@mock-org-admin-abcd1234.iam.gserviceaccount.com"
    project_roles         = []
    impersonation_members = []
  }
}

variables {
  project_prefix        = "mock-org"
  org_id                = "123456789"
  billing_account       = "ABCDEF-123456-789012"
  admin_email           = "admin@example.com"
  tfc_organization      = "my-tfc-org"
  enable_tfc_oidc       = true
  workload_environments = ["dev", "prod"]
}

run "admin_sa_keeps_only_bootstrap_roles" {
  command = plan

  assert {
    condition = sort([
      for k, m in merge(google_organization_iam_member.stage_org_roles, google_organization_iam_member.stage_org_security_admin) :
      m.role if startswith(k, "bootstrap-apply|")
    ]) == sort(["roles/iam.organizationRoleAdmin", "roles/iam.securityAdmin", "roles/resourcemanager.organizationViewer"])
    error_message = "terraform-admin (bootstrap apply) must hold only org IAM admin, org role admin (plan viewer custom role) + org viewer at the org node."
  }

  assert {
    condition = alltrue([
      for k, m in merge(google_organization_iam_member.stage_org_roles, google_organization_iam_member.stage_org_security_admin) :
      m.member == "serviceAccount:terraform-admin@mock-org-admin-abcd1234.iam.gserviceaccount.com" if startswith(k, "bootstrap-apply|")
    ])
    error_message = "bootstrap-apply grants must target the terraform-admin SA."
  }

  assert {
    condition     = length([for k, m in google_billing_account_iam_member.stage_billing_roles : k if startswith(k, "bootstrap-apply|")]) == 0
    error_message = "terraform-admin must no longer hold a billing-account role (costsManager moved to organization-apply)."
  }
}

run "per_stage_plan_and_apply_sas_created" {
  command = plan

  assert {
    condition = sort(keys(google_service_account.stage)) == sort([
      "bootstrap-plan",
      "organization-plan", "organization-apply",
      "projects-plan", "projects-apply",
      "network-hub-plan", "network-hub-apply",
      "wl-dev-plan", "wl-dev-apply",
      "wl-prod-plan", "wl-prod-apply",
    ])
    error_message = "A plan + apply SA must exist per control-plane stage (bootstrap apply = terraform-admin) and per workload environment."
  }

  assert {
    condition     = google_service_account.stage["wl-dev-apply"].account_id == "mock-org-wl-dev-apply" && google_service_account.stage["organization-plan"].account_id == "mock-org-organization-plan"
    error_message = "SA account IDs must follow <prefix>-<stage>-<phase> / <prefix>-wl-<env>-<phase>."
  }
}

run "workload_sas_have_no_org_level_iam" {
  command = plan

  assert {
    condition = length([
      for k in concat(keys(google_organization_iam_member.stage_org_roles), keys(google_organization_iam_member.stage_org_security_admin)) :
      k if startswith(k, "wl-")
    ]) == 0
    error_message = "Workload SAs must not hold ANY org-level IAM binding."
  }

  assert {
    condition     = length([for k in keys(google_project_iam_member.stage_admin_project_roles) : k if startswith(k, "wl-")]) == 0
    error_message = "Workload SAs must not hold any role on the admin/automation project."
  }

  assert {
    condition     = sort([for k, b in google_billing_account_iam_member.stage_billing_roles : b.role if startswith(k, "wl-dev-")]) == sort(["roles/billing.costsManager", "roles/billing.user", "roles/billing.viewer"])
    error_message = "Workload SAs get only billing-account scoped budget roles (plan: viewer, apply: costsManager)."
  }
}

run "plan_sas_hold_no_write_roles" {
  command = plan

  assert {
    condition = length([
      for k, v in merge(
        google_organization_iam_member.stage_org_roles,
        google_organization_iam_member.stage_org_security_admin,
        google_project_iam_member.stage_admin_project_roles,
        google_billing_account_iam_member.stage_billing_roles,
      ) : k if endswith(split("|", k)[0], "-plan") && can(regex("(?i)(admin|editor|owner|creator|writer|\\.user$|costsManager)", v.role))
    ]) == 0
    error_message = "Plan-phase SAs must be strictly read-only: no *admin, editor, owner, creator, writer, *.user or costsManager role."
  }

  assert {
    condition     = length([for k, v in google_organization_iam_member.stage_org_roles : k if endswith(split("|", k)[0], "-plan")]) > 0
    error_message = "Plan SAs must still receive their read-only org roles (guard against a vacuous pass)."
  }
}

run "stage_apply_sas_are_least_privilege" {
  command = plan

  assert {
    condition     = contains([for k, m in google_organization_iam_member.stage_org_roles : m.role if startswith(k, "organization-apply|")], "roles/orgpolicy.policyAdmin")
    error_message = "orgpolicy.policyAdmin must move to the organization apply SA."
  }

  assert {
    condition = sort([
      for k, m in google_organization_iam_member.stage_org_roles : split("|", k)[0] if m.role == "roles/accesscontextmanager.policyAdmin"
    ]) == sort(["network-hub-apply", "organization-apply"])
    error_message = "accesscontextmanager.policyAdmin belongs to the network-hub apply SA (hub perimeter) and the organization apply SA (creates the per-environment scoped policies) only."
  }

  assert {
    condition     = sort([for k, m in google_organization_iam_member.stage_org_security_admin : split("|", k)[0]]) == sort(["bootstrap-apply", "organization-apply"])
    error_message = "Only the bootstrap and organization apply SAs may hold org-level iam.securityAdmin."
  }

  assert {
    condition     = length(google_organization_iam_member.projects_delegated_folder_iam) == 0 && !contains(output.org_role_grants["projects-apply"], "roles/resourcemanager.folderIamAdmin")
    error_message = "projects-apply must NOT hold folderIamAdmin at the org node by default: gcp-organization binds it per target folder."
  }

  assert {
    condition     = contains(output.delegated_workload_folder_roles, "roles/compute.admin") && !contains(output.delegated_workload_folder_roles, "roles/compute.orgFirewallPolicyAdmin") && contains(output.delegated_network_folder_roles, "roles/compute.orgFirewallPolicyAdmin") && !contains(output.delegated_network_folder_roles, "roles/secretmanager.admin")
    error_message = "the per-folder delegation allow-lists must be split: workload roles for env folders, network roles for the shared folder."
  }
}

run "legacy_org_level_folder_delegation_is_opt_in" {
  command = plan

  variables {
    enable_org_level_folder_iam_delegation = true
  }

  assert {
    condition     = strcontains(google_organization_iam_member.projects_delegated_folder_iam[0].condition[0].expression, "modifiedGrantsByRole") && !strcontains(google_organization_iam_member.projects_delegated_folder_iam[0].condition[0].expression, "roles/owner") && strcontains(google_organization_iam_member.projects_delegated_folder_iam[0].condition[0].expression, "'roles/compute.admin'")
    error_message = "the legacy org-level delegation must still be a conditional grant limited to the folder role lists (never roles/owner)."
  }
}

run "plan_identities_get_metadata_only_viewer_role" {
  command = plan

  assert {
    condition     = google_organization_iam_custom_role.plan_viewer[0].role_id == "landingZonePlanViewer" && google_organization_iam_custom_role.plan_viewer[0].org_id == "123456789"
    error_message = "the plan viewer custom role must be created at the org node."
  }

  assert {
    condition = length(setintersection(toset(google_organization_iam_custom_role.plan_viewer[0].permissions), toset([
      "storage.objects.get", "storage.objects.list", "bigquery.tables.getData", "secretmanager.versions.access",
      "cloudkms.cryptoKeyVersions.useToDecrypt", "logging.logEntries.list", "logging.privateLogEntries.list",
    ]))) == 0 && contains(google_organization_iam_custom_role.plan_viewer[0].permissions, "storage.buckets.get")
    error_message = "the plan viewer role must read bucket metadata but never object, table, secret, decrypt or log-entry data."
  }

  assert {
    condition = length([
      for k, v in merge(google_organization_iam_member.stage_org_roles, google_project_iam_member.stage_admin_project_roles) :
      k if endswith(split("|", k)[0], "-plan") && contains(["roles/viewer", "roles/editor", "roles/owner"], v.role)
    ]) == 0
    error_message = "no plan identity may hold roles/viewer (data read), editor or owner on the org or admin project."
  }

  assert {
    condition     = contains(keys(google_project_iam_member.stage_admin_project_roles), "organization-plan|organizations/123456789/roles/landingZonePlanViewer")
    error_message = "organization-plan must get the plan viewer custom role on the admin project in place of roles/viewer."
  }

  assert {
    condition     = !contains(output.workload_folder_roles.plan, "roles/viewer") && contains(output.workload_folder_roles.plan, "organizations/123456789/roles/landingZonePlanViewer") && contains(output.delegated_workload_folder_roles, "organizations/123456789/roles/landingZonePlanViewer")
    error_message = "workload plan folder roles must carry the custom plan viewer role (and its delegation), not roles/viewer."
  }
}

run "workload_access_policy_grants_are_not_org_wide" {
  command = plan

  variables {
    vpc_sc_access_policy_id = "987654321"
  }

  assert {
    condition     = length(google_access_context_manager_access_policy_iam_member.workload) == 0
    error_message = "by default no workload SA may be granted on the org-wide access policy (a dev apply could edit prod/hub perimeters)."
  }
}

run "legacy_org_access_policy_grants_are_opt_in" {
  command = plan

  variables {
    vpc_sc_access_policy_id                = "987654321"
    enable_legacy_org_access_policy_grants = true
  }

  assert {
    condition     = google_access_context_manager_access_policy_iam_member.workload["wl-prod-apply"].role == "roles/accesscontextmanager.policyEditor" && google_access_context_manager_access_policy_iam_member.workload["wl-prod-apply"].name == "accessPolicies/987654321"
    error_message = "the legacy mode must still grant policyEditor on the org-wide policy."
  }
}

run "production_workspaces_must_be_bound_by_id" {
  command = plan

  variables {
    production_workload_environments      = ["prod"]
    phase0_admin_impersonation_expires_at = "2026-12-31T00:00:00Z"
  }

  # Hard failure (precondition), not a warning: a production org must not plan
  # with name-bound WIF trusts (nor with an unbound gcp-guardrails workspace).
  expect_failures = [terraform_data.production_workspaces_bound_by_id, terraform_data.guardrails_workspace_bound_by_id]
}

run "production_workspaces_bound_by_id_pass" {
  command = plan

  variables {
    production_workload_environments      = ["prod"]
    phase0_admin_impersonation_expires_at = "2026-12-31T00:00:00Z"
    tfc_workspace_ids = {
      "gcp-bootstrap"     = "ws-Boot1"
      "gcp-organization"  = "ws-Org1"
      "gcp-projects"      = "ws-Proj1"
      "gcp-network-hub"   = "ws-Hub1"
      "gcp-workload-prod" = "ws-Prod1"
      "gcp-guardrails"    = "ws-Guard1"
    }
  }

  assert {
    condition     = length(output.production_workspaces_bound_by_name) == 0
    error_message = "with every production workspace ID supplied nothing may be reported as name-bound."
  }
}

run "tfc_bindings_are_phase_scoped" {
  command = plan

  assert {
    condition     = strcontains(module.tfc_oidc[0].tfc_attribute_condition, "assertion.terraform_organization_name == 'my-tfc-org'")
    error_message = "TFC provider condition must pin the TFC organization."
  }

  assert {
    condition = sort(keys(module.tfc_oidc[0].tfc_binding_members)) == sort([
      "gcp-bootstrap:plan", "gcp-bootstrap:apply",
      "gcp-organization:plan", "gcp-organization:apply",
      "gcp-projects:plan", "gcp-projects:apply",
      "gcp-network-hub:plan", "gcp-network-hub:apply",
      "gcp-workload-dev:plan", "gcp-workload-dev:apply",
      "gcp-workload-prod:plan", "gcp-workload-prod:apply",
    ])
    error_message = "Every workspace must get exactly one :plan and one :apply binding."
  }

  assert {
    condition     = output.tfc_apply_service_accounts["gcp-bootstrap"] == "terraform-admin@mock-org-admin-abcd1234.iam.gserviceaccount.com"
    error_message = "Only the gcp-bootstrap apply phase may use the terraform-admin SA."
  }

  assert {
    condition     = sort(keys(output.tfc_plan_service_accounts)) == sort(keys(output.tfc_apply_service_accounts)) && contains(keys(output.tfc_plan_service_accounts), "gcp-workload-prod")
    error_message = "tfc_plan_service_accounts / tfc_apply_service_accounts must cover the same workspaces, keyed by TFC workspace name."
  }
}

run "tfc_pins_org_id_project_and_workspace_id" {
  command = plan

  variables {
    tfc_organization_id = "org-Abc123"
    tfc_project_ids     = ["prj-Xyz789"]
    tfc_workspace_ids   = { "gcp-organization" = "ws-Org111" }
  }

  assert {
    condition     = strcontains(module.tfc_oidc[0].tfc_attribute_condition, "assertion.terraform_organization_id == 'org-Abc123'") && strcontains(module.tfc_oidc[0].tfc_attribute_condition, "assertion.terraform_project_id in ['prj-Xyz789']")
    error_message = "Optional TFC org ID and project allow-list must be pinned in the provider condition."
  }
}

run "github_wif_disabled_by_default" {
  command = plan

  assert {
    condition     = length(module.gh_oidc) == 0 && output.github_oidc_provider_name == null
    error_message = "The GitHub WIF pool must be off by default (no workflow uses it)."
  }
}

run "github_wif_pins_immutable_ids_and_readonly_sa" {
  command = plan

  override_resource {
    target          = module.gh_oidc[0].google_iam_workload_identity_pool.pool
    override_during = plan
    values = {
      name = "projects/1/locations/global/workloadIdentityPools/github-pool"
    }
  }

  variables {
    enable_github_wif          = true
    github_org                 = "my-org"
    github_repo                = "my-repo"
    github_repository_id       = "424242"
    github_repository_owner_id = "777"
  }

  assert {
    condition     = module.gh_oidc[0].github_attribute_condition == "assertion.repository_owner_id == \"777\""
    error_message = "the GitHub provider condition must be exactly the canonical owner pin (what custom.wifProviderTenantPinned accepts)."
  }

  assert {
    condition     = keys(module.gh_oidc[0].github_binding_members) == ["organization-plan"] && endswith(module.gh_oidc[0].github_binding_members["organization-plan"], "/attribute.repo_ref/424242/refs/heads/main")
    error_message = "the plan SA must be bound to the immutable repository_id on refs/heads/main only (attribute.repo_ref)."
  }

  assert {
    condition     = keys(module.gh_oidc[0].github_binding_service_accounts) == ["organization-plan"]
    error_message = "GitHub must be bound ONLY to the read-only organization plan SA, never the admin SA."
  }
}

# Audit Modularity-H: the admin project is created through the shared project
# primitive (modules/gcp/project); the stage owns only the naming scheme.
run "admin_project_uses_project_primitive" {
  command = plan

  assert {
    condition     = module.admin_project.name == "mock-org-admin"
    error_message = "Admin project display name must be <prefix>-admin."
  }

  assert {
    condition     = module.admin_project.parent == "organizations/123456789"
    error_message = "Admin project must be created directly under the organization."
  }

  assert {
    condition     = contains(module.admin_project.services, "iamcredentials.googleapis.com") && contains(module.admin_project.services, "cloudresourcemanager.googleapis.com")
    error_message = "Admin project must enable the WIF / resource-manager APIs."
  }

  assert {
    condition     = module.admin_project.labels["purpose"] == "administration"
    error_message = "Admin project must carry the administration labels."
  }
}

# By default the organization apply SA does NOT hold roles/iam.denyAdmin;
# a dedicated guardrails SA does, impersonable only by guardrail_owner_members.
run "guardrail_owner_is_separate_by_default" {
  command = plan

  variables {
    guardrail_owner_members = ["group:guardrail-owners@example.com"]
  }

  assert {
    condition     = !contains([for k, m in google_organization_iam_member.stage_org_roles : m.role], "roles/iam.denyAdmin")
    error_message = "No stage identity (in particular organization-apply) may hold roles/iam.denyAdmin in separate mode."
  }

  assert {
    condition     = google_service_account.guardrails[0].account_id == "mock-org-guardrails-apply"
    error_message = "The guardrails SA must be <prefix>-guardrails-apply."
  }

  assert {
    condition     = google_organization_iam_member.guardrails["roles/iam.denyAdmin"].role == "roles/iam.denyAdmin"
    error_message = "The guardrails SA must hold roles/iam.denyAdmin at the org."
  }

  assert {
    condition     = keys(google_service_account_iam_member.guardrails_impersonation) == ["group:guardrail-owners@example.com"] && google_service_account_iam_member.guardrails_impersonation["group:guardrail-owners@example.com"].role == "roles/iam.serviceAccountTokenCreator"
    error_message = "Only guardrail_owner_members may impersonate the guardrails SA."
  }

  assert {
    condition     = output.guardrail_owner_mode == "separate"
    error_message = "guardrail_owner_mode must default to separate."
  }
}

# The security-team gcp-guardrails workspace authenticates as the guardrails
# SAs, bound by its immutable workspace ID only: plan to the read-only
# guardrails-plan SA, apply to the denyAdmin guardrails-apply SA.
run "guardrails_wif_bound_by_workspace_id" {
  command = plan

  variables {
    tfc_workspace_ids = { "gcp-guardrails" = "ws-Guard1" }
  }

  override_resource {
    target          = module.tfc_oidc[0].google_iam_workload_identity_pool.pool
    override_during = plan
    values = {
      name = "projects/1/locations/global/workloadIdentityPools/tfc-pool"
    }
  }

  assert {
    condition     = module.tfc_oidc[0].tfc_binding_members["gcp-guardrails:apply"] == "principalSet://iam.googleapis.com/projects/1/locations/global/workloadIdentityPools/tfc-pool/attribute.workspace_id_phase/ws-Guard1:apply" && module.tfc_oidc[0].tfc_binding_members["gcp-guardrails:plan"] == "principalSet://iam.googleapis.com/projects/1/locations/global/workloadIdentityPools/tfc-pool/attribute.workspace_id_phase/ws-Guard1:plan"
    error_message = "gcp-guardrails must be WIF-bound by its workspace ID, per run phase."
  }

  assert {
    condition     = google_service_account.guardrails_plan[0].account_id == "mock-org-guardrails-plan" && contains(keys(google_organization_iam_member.guardrails_plan), "roles/iam.denyReviewer") && !contains(keys(google_organization_iam_member.guardrails_plan), "roles/iam.denyAdmin")
    error_message = "the guardrails plan SA must be read-only (denyReviewer, no denyAdmin)."
  }

  assert {
    condition     = output.guardrails_workspace_bound_by_id && contains(keys(output.tfc_apply_service_accounts), "gcp-guardrails") && contains(keys(output.tfc_plan_service_accounts), "gcp-guardrails")
    error_message = "tfc-admin needs the gcp-guardrails plan/apply SA emails for its dynamic credentials."
  }

  # The PAM-gated break-glass path is kept.
  assert {
    condition     = length(google_service_account_iam_member.guardrails_impersonation) == 0 && contains(keys(google_organization_iam_member.guardrails), "roles/iam.denyAdmin")
    error_message = "the guardrails SA keeps denyAdmin; impersonation stays limited to guardrail_owner_members."
  }
}

# Never by name: without the ID there is no binding at all, and a production
# estate fails the plan.
run "guardrails_wif_never_bound_by_name" {
  command = plan

  assert {
    condition     = !contains(keys(module.tfc_oidc[0].tfc_binding_members), "gcp-guardrails:apply") && !contains(keys(module.tfc_oidc[0].tfc_binding_members), "gcp-guardrails:plan")
    error_message = "gcp-guardrails must never be WIF-bound by its (squattable) name."
  }

  assert {
    condition     = output.guardrails_workspace_bound_by_id == false && !contains(keys(output.tfc_apply_service_accounts), "gcp-guardrails")
    error_message = "an unbound gcp-guardrails workspace must be reported and get no dynamic credentials."
  }
}

run "guardrails_workspace_id_required_in_production" {
  command = plan

  variables {
    production_workload_environments      = ["prod"]
    phase0_admin_impersonation_expires_at = "2026-12-31T00:00:00Z"
    tfc_workspace_ids                     = { "gcp-bootstrap" = "ws-Boot1", "gcp-organization" = "ws-Org1", "gcp-projects" = "ws-Proj1", "gcp-network-hub" = "ws-Hub1", "gcp-workload-prod" = "ws-Prod1" }
  }

  expect_failures = [terraform_data.guardrails_workspace_bound_by_id]
}

run "guardrails_workspace_wif_can_be_disabled" {
  command = plan

  variables {
    guardrails_workspace                  = null
    production_workload_environments      = ["prod"]
    phase0_admin_impersonation_expires_at = "2026-12-31T00:00:00Z"
    tfc_workspace_ids                     = { "gcp-bootstrap" = "ws-Boot1", "gcp-organization" = "ws-Org1", "gcp-projects" = "ws-Proj1", "gcp-network-hub" = "ws-Hub1", "gcp-workload-prod" = "ws-Prod1" }
  }

  assert {
    condition     = length(google_service_account.guardrails_plan) == 0 && !contains(keys(output.tfc_apply_service_accounts), "gcp-guardrails")
    error_message = "guardrails_workspace = null must keep the PAM-only path (no workspace identity)."
  }
}

run "guardrail_owner_legacy_organization_mode" {
  command = plan

  variables {
    guardrail_owner_mode = "organization"
  }

  assert {
    condition     = contains(keys(google_organization_iam_member.stage_org_roles), "organization-apply|roles/iam.denyAdmin")
    error_message = "Legacy organization mode must keep denyAdmin on organization-apply."
  }

  assert {
    condition     = length(google_service_account.guardrails) == 0 && length(google_organization_iam_member.guardrails) == 0 && length(google_service_account.guardrails_plan) == 0 && !contains(keys(output.tfc_apply_service_accounts), "gcp-guardrails")
    error_message = "Legacy organization mode must not create the guardrails SAs or bind gcp-guardrails."
  }
}

# The phase-0 human impersonation of terraform-admin is switchable.
run "phase0_admin_impersonation_can_be_revoked" {
  command = plan

  variables {
    enable_phase0_admin_impersonation = false
  }

  assert {
    condition     = length(output.phase0_admin_impersonation_members) == 0
    error_message = "enable_phase0_admin_impersonation = false must remove the human impersonation of terraform-admin."
  }
}

run "phase0_admin_impersonation_default_on" {
  command = plan

  assert {
    condition     = length(output.phase0_admin_impersonation_members) == 1 && contains(output.phase0_admin_impersonation_members, "user:admin@example.com")
    error_message = "The first (phase-0) apply needs the admin user impersonation by default."
  }
}

run "principal_access_boundary_grants_are_opt_in" {
  command = plan

  variables {
    enable_principal_access_boundary = true
  }

  assert {
    condition     = contains(keys(google_organization_iam_member.stage_org_roles), "organization-apply|roles/iam.principalAccessBoundaryAdmin") && contains(keys(google_project_iam_member.stage_admin_project_roles), "organization-apply|roles/resourcemanager.projectIamAdmin")
    error_message = "enable_principal_access_boundary must grant organization-apply PAB admin (org) and projectIamAdmin (admin project)."
  }

  assert {
    condition     = contains(keys(google_organization_iam_member.stage_org_roles), "organization-plan|roles/iam.principalAccessBoundaryViewer")
    error_message = "enable_principal_access_boundary must grant organization-plan the PAB viewer role."
  }
}

# A production estate must not keep an open-ended human path to terraform-admin:
# the plan fails (precondition), it does not merely warn.
run "production_without_expiry_fails" {
  command = plan

  variables {
    production_workload_environments = ["prod"]
    tfc_workspace_ids                = { "gcp-bootstrap" = "ws-Boot1", "gcp-organization" = "ws-Org1", "gcp-projects" = "ws-Proj1", "gcp-network-hub" = "ws-Hub1", "gcp-workload-prod" = "ws-Prod1", "gcp-guardrails" = "ws-Guard1" }
  }

  expect_failures = [terraform_data.phase0_impersonation_is_time_boxed]
}

run "production_with_expiry_plans" {
  command = plan

  variables {
    production_workload_environments      = ["prod"]
    phase0_admin_impersonation_expires_at = "2026-12-31T00:00:00Z"
    tfc_workspace_ids                     = { "gcp-bootstrap" = "ws-Boot1", "gcp-organization" = "ws-Org1", "gcp-projects" = "ws-Proj1", "gcp-network-hub" = "ws-Hub1", "gcp-workload-prod" = "ws-Prod1", "gcp-guardrails" = "ws-Guard1" }
  }

  assert {
    condition     = length(output.production_workspaces_bound_by_name) == 0
    error_message = "a time-boxed production estate must plan."
  }
}

# ─── Scaffolded-config path (QUICK_START GCP) ────────────────────────────────
# tests/fixtures/landing-zone.scaffolded.yaml is the output of
# scripts/init-landing-zone.sh (org.profile production, a prod environment),
# with the 7-day phase-0 expiry replaced by a fixed far-future literal. The
# stage does not read YAML; these runs feed it the scaffolded VALUES, the way
# envs/gcp/bootstrap/config.tf would.

run "scaffolded_values_without_ids_fail_with_hint" {
  command = plan

  variables {
    project_prefix                        = yamldecode(file("tests/fixtures/landing-zone.scaffolded.yaml")).org.prefix
    admin_email                           = yamldecode(file("tests/fixtures/landing-zone.scaffolded.yaml")).gcp.admin_email
    tfc_organization                      = yamldecode(file("tests/fixtures/landing-zone.scaffolded.yaml")).org.tfc.organization
    workload_environments                 = keys(yamldecode(file("tests/fixtures/landing-zone.scaffolded.yaml")).gcp.environments)
    production_workload_environments      = [for k, e in yamldecode(file("tests/fixtures/landing-zone.scaffolded.yaml")).gcp.environments : k if e.is_production]
    phase0_admin_impersonation_expires_at = yamldecode(file("tests/fixtures/landing-zone.scaffolded.yaml")).gcp.phase0_admin_impersonation_expires_at
  }

  # No tfc_workspace_ids (a fresh scaffold before `make bootstrap-ids`): the
  # production precondition must fail (its message names the tfc-admin
  # workspace_ids hint). The unbound gcp-guardrails workspace trips its sibling
  # precondition in the same plan, so both are expected.
  expect_failures = [terraform_data.production_workspaces_bound_by_id, terraform_data.guardrails_workspace_bound_by_id]
}

run "scaffolded_values_with_ids_plan" {
  command = plan

  variables {
    project_prefix                        = yamldecode(file("tests/fixtures/landing-zone.scaffolded.yaml")).org.prefix
    admin_email                           = yamldecode(file("tests/fixtures/landing-zone.scaffolded.yaml")).gcp.admin_email
    tfc_organization                      = yamldecode(file("tests/fixtures/landing-zone.scaffolded.yaml")).org.tfc.organization
    workload_environments                 = keys(yamldecode(file("tests/fixtures/landing-zone.scaffolded.yaml")).gcp.environments)
    production_workload_environments      = [for k, e in yamldecode(file("tests/fixtures/landing-zone.scaffolded.yaml")).gcp.environments : k if e.is_production]
    phase0_admin_impersonation_expires_at = yamldecode(file("tests/fixtures/landing-zone.scaffolded.yaml")).gcp.phase0_admin_impersonation_expires_at
    # What `make bootstrap-ids` writes (tfc-admin output gcp_bootstrap_tfvars).
    tfc_workspace_ids = {
      "gcp-bootstrap"     = "ws-Boot1"
      "gcp-organization"  = "ws-Org1"
      "gcp-projects"      = "ws-Proj1"
      "gcp-network-hub"   = "ws-Hub1"
      "gcp-workload-prod" = "ws-Prod1"
      "gcp-guardrails"    = "ws-Guard1"
    }
  }

  assert {
    condition     = length(output.production_workspaces_bound_by_name) == 0
    error_message = "the scaffolded production config plans cleanly once every workspace ID is supplied."
  }
}

# ─── Shared scaffold-matrix fixture (make scaffold-fixtures) ─────────────────
# envs/gcp/bootstrap overrides this stage, so its scaffold runs never reach the
# production precondition. These runs evaluate it against the committed
# scaffolder output; tfc_workspace_ids (written by `make bootstrap-ids` after
# tfc-admin applies) is the operator-supplied input and is never defaulted.

run "scaffold_matrix_without_ids_fails" {
  command = plan

  variables {
    project_prefix                        = yamldecode(file("../../../../tests/fixtures/scaffold/landing-zone.gcp.yaml")).org.prefix
    admin_email                           = yamldecode(file("../../../../tests/fixtures/scaffold/landing-zone.gcp.yaml")).gcp.admin_email
    tfc_organization                      = yamldecode(file("../../../../tests/fixtures/scaffold/landing-zone.gcp.yaml")).org.tfc.organization
    workload_environments                 = keys(yamldecode(file("../../../../tests/fixtures/scaffold/landing-zone.gcp.yaml")).gcp.environments)
    production_workload_environments      = [for k, e in yamldecode(file("../../../../tests/fixtures/scaffold/landing-zone.gcp.yaml")).gcp.environments : k if e.is_production]
    phase0_admin_impersonation_expires_at = yamldecode(file("../../../../tests/fixtures/scaffold/landing-zone.gcp.yaml")).gcp.phase0_admin_impersonation_expires_at
  }

  expect_failures = [terraform_data.production_workspaces_bound_by_id, terraform_data.guardrails_workspace_bound_by_id]
}

run "scaffold_matrix_with_ids_plans" {
  command = plan

  variables {
    project_prefix                        = yamldecode(file("../../../../tests/fixtures/scaffold/landing-zone.gcp.yaml")).org.prefix
    admin_email                           = yamldecode(file("../../../../tests/fixtures/scaffold/landing-zone.gcp.yaml")).gcp.admin_email
    tfc_organization                      = yamldecode(file("../../../../tests/fixtures/scaffold/landing-zone.gcp.yaml")).org.tfc.organization
    workload_environments                 = keys(yamldecode(file("../../../../tests/fixtures/scaffold/landing-zone.gcp.yaml")).gcp.environments)
    production_workload_environments      = [for k, e in yamldecode(file("../../../../tests/fixtures/scaffold/landing-zone.gcp.yaml")).gcp.environments : k if e.is_production]
    phase0_admin_impersonation_expires_at = yamldecode(file("../../../../tests/fixtures/scaffold/landing-zone.gcp.yaml")).gcp.phase0_admin_impersonation_expires_at
    tfc_workspace_ids = {
      "gcp-bootstrap"     = "ws-Boot1"
      "gcp-organization"  = "ws-Org1"
      "gcp-projects"      = "ws-Proj1"
      "gcp-network-hub"   = "ws-Hub1"
      "gcp-workload-prod" = "ws-Prod1"
      "gcp-guardrails"    = "ws-Guard1"
    }
  }

  assert {
    condition     = length(output.production_workspaces_bound_by_name) == 0
    error_message = "the scaffold's production config plans cleanly once every workspace ID is supplied."
  }
}

# Network Connectivity Center roles are opt-in and folder-scoped: the network
# SAs (shared folder) manage the hub, each workload SA (its env folder) its
# spoke. None reaches the org node.
run "ncc_roles_off_by_default" {
  command = plan

  assert {
    condition = !anytrue([
      for r in concat(output.workload_folder_roles.plan, output.workload_folder_roles.apply, output.network_folder_roles.plan, output.network_folder_roles.apply) :
      startswith(r, "roles/networkconnectivity.")
    ])
    error_message = "No NCC role may be granted unless enable_network_connectivity_center = true."
  }
}

run "ncc_roles_are_folder_scoped_when_enabled" {
  command = plan

  variables {
    enable_network_connectivity_center = true
  }

  assert {
    condition = (
      contains(output.network_folder_roles.apply, "roles/networkconnectivity.hubAdmin") &&
      contains(output.network_folder_roles.apply, "roles/networkconnectivity.spokeAdmin") &&
      contains(output.network_folder_roles.plan, "roles/networkconnectivity.hubViewer")
    )
    error_message = "The network-hub SAs must get hubAdmin + spokeAdmin (plan: hubViewer) on the shared folder."
  }

  assert {
    condition = (
      contains(output.workload_folder_roles.apply, "roles/networkconnectivity.spokeAdmin") &&
      !contains(output.workload_folder_roles.apply, "roles/networkconnectivity.hubAdmin") &&
      contains(output.workload_folder_roles.plan, "roles/networkconnectivity.hubViewer")
    )
    error_message = "Each workload SA must get spokeAdmin only (plan: hubViewer) on its environment folder."
  }

  assert {
    condition     = contains(output.delegated_network_folder_roles, "roles/networkconnectivity.hubAdmin") && !contains(output.delegated_workload_folder_roles, "roles/networkconnectivity.hubAdmin")
    error_message = "The delegation allow-lists must carry the NCC roles to the matching folders only."
  }

  assert {
    condition     = !anytrue([for k, m in google_organization_iam_member.stage_org_roles : startswith(m.role, "roles/networkconnectivity.")])
    error_message = "No NCC role may be granted at the org node."
  }

  assert {
    condition     = !anytrue([for r in output.network_folder_roles.plan : endswith(r, "Admin")]) && !anytrue([for r in output.workload_folder_roles.plan : endswith(r, "Admin")])
    error_message = "Plan SAs must get only the NCC viewer role."
  }
}
