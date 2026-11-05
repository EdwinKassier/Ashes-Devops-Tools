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
  project_prefix   = "acme"
  domain           = "example.com"
  billing_account  = "000000-111111-222222"
  admin_email      = "admin@example.com"
  tfc_organization = "acme-tfc"
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
