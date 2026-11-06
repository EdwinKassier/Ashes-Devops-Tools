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
  # Isolate the suite from any committed config/landing-zone.yaml.
  landing_zone_config_path = ""
  project_prefix           = "acme"
  domain                   = "example.com"
  billing_account          = "000000-111111-222222"
  admin_email              = "admin@example.com"
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
    admin_project_id           = "acme-admin-abcd"
    admin_project_number       = "123456789012"
    terraform_admin_email      = "terraform-admin@acme-admin-abcd.iam.gserviceaccount.com"
    suffix                     = "abcd"
    github_oidc_pool_id        = "gh-pool"
    github_oidc_pool_name      = "//iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/gh-pool"
    github_oidc_provider_name  = "//iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/gh-pool/providers/gh"
    tfc_oidc_pool_id           = "tfc-pool"
    tfc_oidc_pool_name         = "//iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/tfc-pool"
    tfc_oidc_provider_name     = "//iam.googleapis.com/projects/123/locations/global/workloadIdentityPools/tfc-pool/providers/tfc"
    resman_email               = "acme-organization-apply@acme-admin-abcd.iam.gserviceaccount.com"
    tfc_workload_provider_name = "projects/123/locations/global/workloadIdentityPools/tfc-pool/providers/terraform-cloud"
    tfc_attribute_condition    = "assertion.terraform_organization_name == 'acme'"
    tfc_plan_service_accounts = {
      "gcp-bootstrap"    = "acme-bootstrap-plan@acme-admin-abcd.iam.gserviceaccount.com"
      "gcp-workload-dev" = "acme-wl-dev-plan@acme-admin-abcd.iam.gserviceaccount.com"
    }
    tfc_apply_service_accounts = {
      "gcp-bootstrap"    = "terraform-admin@acme-admin-abcd.iam.gserviceaccount.com"
      "gcp-workload-dev" = "acme-wl-dev-apply@acme-admin-abcd.iam.gserviceaccount.com"
    }
    stage_service_accounts = {}
    workload_service_accounts = {
      dev = {
        plan  = "acme-wl-dev-plan@acme-admin-abcd.iam.gserviceaccount.com"
        apply = "acme-wl-dev-apply@acme-admin-abcd.iam.gserviceaccount.com"
      }
    }
    workload_folder_roles = { plan = ["roles/viewer"], apply = ["roles/compute.admin"] }
    network_folder_roles  = { plan = ["roles/compute.viewer"], apply = ["roles/compute.networkAdmin"] }
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

# The tfc-admin root consumes exactly these three output names.
run "tfc_identity_output_contract" {
  command = plan

  assert {
    condition     = output.tfc_plan_service_accounts["gcp-workload-dev"] == "acme-wl-dev-plan@acme-admin-abcd.iam.gserviceaccount.com" && output.tfc_apply_service_accounts["gcp-workload-dev"] == "acme-wl-dev-apply@acme-admin-abcd.iam.gserviceaccount.com"
    error_message = "tfc_plan_service_accounts / tfc_apply_service_accounts must be re-exported keyed by TFC workspace name."
  }

  assert {
    condition     = output.tfc_workload_provider_name == "projects/123/locations/global/workloadIdentityPools/tfc-pool/providers/terraform-cloud"
    error_message = "tfc_workload_provider_name must be re-exported as the full provider resource name."
  }

  assert {
    condition     = output.workload_service_accounts["dev"].apply == "acme-wl-dev-apply@acme-admin-abcd.iam.gserviceaccount.com" && can(output.workload_folder_roles.apply) && can(output.network_folder_roles.plan)
    error_message = "workload_service_accounts and the folder-role lists must be re-exported for gcp-projects."
  }
}
