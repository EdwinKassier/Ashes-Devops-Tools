# Variable validation tests for the stages/bootstrap module.
# All runs use mock_provider so no GCP credentials are required.
#
# override_module is required for module.terraform_admin_sa because its
# service account email is an apply-time value — the for_each in the
# workload_identity child module uses it as a map key, causing plan failures
# unless the value is provided statically via override_module.

mock_provider "google" {}
mock_provider "random" {}

variables {
  project_prefix   = "mock-org"
  org_id           = "123456789"
  billing_account  = "ABCDEF-123456-789012"
  admin_email      = "admin@example.com"
  github_org       = "my-org"
  github_repo      = "my-repo"
  tfc_organization = "my-tfc-org"
}

# ── tfc_workspaces guard (cross-variable precondition) ─────────────────────────

run "accepts_tfc_oidc_disabled_with_empty_workspaces" {
  command = plan

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
    enable_tfc_oidc  = false
    tfc_organization = null
    tfc_workspaces   = []
  }
}

run "accepts_tfc_oidc_enabled_with_workspaces" {
  command = plan

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
    enable_tfc_oidc = true
    tfc_workspaces  = ["organization", "apps-dev"]
  }
}

run "accepts_default_tfc_workspaces_when_tfc_disabled" {
  command = plan

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
    enable_tfc_oidc  = false
    tfc_organization = null
  }
}
