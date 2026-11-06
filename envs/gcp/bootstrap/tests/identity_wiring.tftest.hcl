# C2 wiring test for the gcp-bootstrap root WITHOUT overriding the stage: the
# environments map must drive one plan/apply SA pair per env, workload SAs must
# get no org-level IAM, and the GitHub pool must be off by default.
# Data sources are mocked; no GCP credentials required.

mock_provider "google" {
  mock_data "google_organization" {
    defaults = {
      org_id = "123456789012"
    }
  }
  mock_data "google_billing_account" {
    defaults = {
      id = "000000-111111-222222"
    }
  }
}
mock_provider "google-beta" {}
mock_provider "random" {}

variables {
  # Isolate the suite from any committed config/landing-zone.yaml.
  landing_zone_config_path = ""
  project_prefix           = "acme"
  domain                   = "example.com"
  billing_account          = "000000-111111-222222"
  admin_email              = "admin@example.com"
  tfc_organization         = "acme-tfc"
  environments = {
    dev = {
      display_name            = "Development"
      region                  = "europe-west1"
      cidr_block              = "10.10.0.0/16"
      budget_monthly_limit    = 100
      iam_group_role_bindings = {}
    }
    prod = {
      display_name            = "Production"
      region                  = "europe-west1"
      cidr_block              = "10.20.0.0/16"
      budget_monthly_limit    = 100
      iam_group_role_bindings = {}
    }
  }
}

run "environments_drive_workload_identities" {
  command = plan

  assert {
    condition     = toset(keys(output.workload_service_accounts)) == toset(["dev", "prod"])
    error_message = "Each environment key must get its own workload SA pair."
  }

  assert {
    condition     = contains(keys(output.tfc_plan_service_accounts), "gcp-workload-prod") && contains(keys(output.tfc_apply_service_accounts), "gcp-organization")
    error_message = "tfc_plan/apply_service_accounts must be keyed by TFC workspace name."
  }

  assert {
    condition     = length([for k in keys(module.bootstrap.org_role_grants) : k if startswith(k, "wl-")]) == 0 && contains(keys(module.bootstrap.org_role_grants), "organization-apply")
    error_message = "Workload SAs must not hold any org-level IAM binding."
  }

  assert {
    condition     = output.github_oidc_provider_name == null
    error_message = "GitHub WIF must be off by default."
  }
}

# is_production on an environment drives the workspace-ID check (the warning
# path itself is covered in modules/gcp/stages/bootstrap tests): with every
# production and control-plane workspace bound by ID nothing is reported.
run "production_environment_bound_by_workspace_ids" {
  command = plan

  variables {
    phase0_admin_impersonation_expires_at = "2026-12-31T00:00:00Z"
    tfc_workspace_ids = {
      "gcp-bootstrap"     = "ws-Boot1"
      "gcp-organization"  = "ws-Org1"
      "gcp-projects"      = "ws-Proj1"
      "gcp-network-hub"   = "ws-Hub1"
      "gcp-workload-prod" = "ws-Prod1"
      "gcp-guardrails"    = "ws-Guard1"
    }
    environments = {
      prod = {
        display_name            = "Production"
        region                  = "europe-west1"
        cidr_block              = "10.20.0.0/16"
        budget_monthly_limit    = 100
        iam_group_role_bindings = {}
        is_production           = true
      }
    }
  }

  assert {
    condition     = length(output.production_workspaces_bound_by_name) == 0 && contains(keys(module.bootstrap.tfc_apply_service_accounts), "gcp-workload-prod") && contains(keys(output.tfc_apply_service_accounts), "gcp-guardrails")
    error_message = "with IDs for every production / control-plane workspace (gcp-guardrails included) nothing may be reported as name-bound."
  }
}

run "plan_roles_and_access_policy_defaults" {
  command = plan

  variables {
    vpc_sc_access_policy_id = "987654321"
  }

  assert {
    condition     = !contains(output.workload_folder_roles.plan, "roles/viewer") && contains(output.workload_folder_roles.plan, "organizations/123456789012/roles/landingZonePlanViewer")
    error_message = "workload plan folder roles must use the metadata-only plan viewer custom role, not roles/viewer."
  }

  assert {
    condition     = !contains(module.bootstrap.org_role_grants["projects-apply"], "roles/resourcemanager.folderIamAdmin") && contains(module.bootstrap.org_role_grants["organization-apply"], "roles/accesscontextmanager.policyAdmin")
    error_message = "projects-apply folder delegation must not be org-wide; organization-apply must be able to create the scoped access policies."
  }
}

# Deny-policy ownership defaults to the separate guardrail owner, which
# gcp-organization reads to stop applying deny policies itself.
run "guardrail_owner_defaults_to_separate" {
  command = plan

  assert {
    condition     = output.guardrail_owner_mode == "separate" && !contains(module.bootstrap.org_role_grants["organization-apply"], "roles/iam.denyAdmin")
    error_message = "By default the organization apply SA must not hold roles/iam.denyAdmin; the guardrails SA owns deny policies."
  }
}

# The prod preset ships a placeholder guardrail owner; it must fail until replaced.
run "rejects_placeholder_guardrail_owner" {
  command = plan

  variables {
    guardrail_owner_members = ["group:REPLACE-guardrail-owners@your-domain.invalid"]
  }

  expect_failures = [var.guardrail_owner_members]
}

# gcp.principal_access_boundary is shared with gcp-organization (which binds the
# boundary) and gcp-guardrails (which denies its update/delete/unbind).
run "principal_access_boundary_from_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-pab.yaml"
  }

  assert {
    condition     = local.enable_principal_access_boundary && contains(module.bootstrap.org_role_grants["organization-plan"], "roles/iam.principalAccessBoundaryViewer")
    error_message = "gcp.principal_access_boundary: true must grant the organization SAs the boundary roles."
  }
}
