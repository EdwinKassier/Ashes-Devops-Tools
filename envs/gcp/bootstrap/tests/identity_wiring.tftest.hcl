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
    tfc_workspace_ids = {
      "gcp-bootstrap"     = "ws-Boot1"
      "gcp-organization"  = "ws-Org1"
      "gcp-projects"      = "ws-Proj1"
      "gcp-network-hub"   = "ws-Hub1"
      "gcp-workload-prod" = "ws-Prod1"
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
    condition     = length(output.production_workspaces_bound_by_name) == 0 && contains(keys(module.bootstrap.tfc_apply_service_accounts), "gcp-workload-prod")
    error_message = "with IDs for every production / control-plane workspace nothing may be reported as name-bound."
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
