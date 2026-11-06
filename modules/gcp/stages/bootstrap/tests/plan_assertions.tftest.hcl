# Plan assertions for the bootstrap stage — audit C2 identity model.
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
    error_message = "Workload SAs must not hold ANY org-level IAM binding (C2)."
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
    production_workload_environments = ["prod"]
  }

  expect_failures = [check.production_workspaces_bound_by_id]

  assert {
    condition     = contains(output.production_workspaces_bound_by_name, "gcp-workload-prod") && contains(output.production_workspaces_bound_by_name, "gcp-bootstrap")
    error_message = "the production workload and control-plane workspaces bound by name must be reported."
  }
}

run "production_workspaces_bound_by_id_pass" {
  command = plan

  variables {
    production_workload_environments = ["prod"]
    tfc_workspace_ids = {
      "gcp-bootstrap"     = "ws-Boot1"
      "gcp-organization"  = "ws-Org1"
      "gcp-projects"      = "ws-Proj1"
      "gcp-network-hub"   = "ws-Hub1"
      "gcp-workload-prod" = "ws-Prod1"
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

  variables {
    enable_github_wif          = true
    github_org                 = "my-org"
    github_repo                = "my-repo"
    github_repository_id       = "424242"
    github_repository_owner_id = "777"
  }

  assert {
    condition     = strcontains(module.gh_oidc[0].github_attribute_condition, "assertion.repository_id == '424242'") && strcontains(module.gh_oidc[0].github_attribute_condition, "assertion.repository_owner_id == '777'") && strcontains(module.gh_oidc[0].github_attribute_condition, "refs/heads/main")
    error_message = "GitHub trust must be pinned to the immutable repository_id + repository_owner_id on main."
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
