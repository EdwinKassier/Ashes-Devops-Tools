# Cross-root OUTPUT CONTRACT test for the gcp-bootstrap root (the PRODUCER).
#
# gcp-organization reads admin_project_id / admin_project_number /
# terraform_admin_email / suffix (and the OIDC pool names) from this root via
# terraform_remote_state. Renaming or dropping one breaks gcp-organization at
# plan. This test overrides the bootstrap stage with a known contract and asserts
# the root re-exports it under the agreed names.

mock_provider "google" {}
mock_provider "google-beta" {}
mock_provider "random" {}

variables {
  project_prefix  = "acme"
  domain          = "example.com"
  billing_account = "000000-111111-222222"
  admin_email     = "admin@example.com"
  github_org      = "acme"
  github_repo     = "infra"
  environments = {
    dev = {
      display_name            = "Development"
      region                  = "europe-west1"
      cidr_block              = "10.10.0.0/16"
      budget_monthly_limit    = 100
      iam_group_role_bindings = {}
    }
  }
}

override_module {
  target = module.bootstrap
  outputs = {
    admin_project_id          = "acme-admin-abcd"
    admin_project_number      = "123456789012"
    terraform_admin_email     = "terraform-admin@acme-admin-abcd.iam.gserviceaccount.com"
    suffix                    = "abcd"
    github_oidc_pool_id       = "gh-pool"
    github_oidc_pool_name     = "//iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/gh-pool"
    github_oidc_provider_name = "//iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/gh-pool/providers/gh"
    tfc_oidc_pool_id          = "tfc-pool"
    tfc_oidc_pool_name        = "//iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/tfc-pool"
    tfc_oidc_provider_name    = "//iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/tfc-pool/providers/tfc"
    resman_email              = null
  }
}

run "bootstrap_output_contract" {
  command = plan

  assert {
    condition     = output.admin_project_id == "acme-admin-abcd" && output.admin_project_number == "123456789012" && output.terraform_admin_email == "terraform-admin@acme-admin-abcd.iam.gserviceaccount.com" && output.suffix == "abcd"
    error_message = "bootstrap root must re-export the admin project + Terraform SA + suffix contract consumed by gcp-organization."
  }

  assert {
    condition     = can(output.github_oidc_provider_name) && can(output.tfc_oidc_provider_name) && can(output.github_oidc_pool_id) && can(output.tfc_oidc_pool_id)
    error_message = "bootstrap root must re-export the WIF pool and provider contract."
  }
}
