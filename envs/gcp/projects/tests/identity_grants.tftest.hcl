# Wiring test for the gcp-projects root: the workload / network-hub SAs read
# from gcp-bootstrap remote state are granted folder roles by the REAL projects
# stage (not overridden here) — workload SAs on their own env folder only.
# No GCP credentials required.

mock_provider "google" {}
mock_provider "google-beta" {}
mock_provider "random" {}

variables {
  # Isolate the suite from any committed config/landing-zone.yaml.
  landing_zone_config_path = ""
  project_prefix           = "acme"
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

override_data {
  target = data.terraform_remote_state.gcp_bootstrap
  values = {
    outputs = {
      admin_project_id = "acme-admin-abcd"
      suffix           = "abcd"
      workload_service_accounts = {
        dev = {
          plan  = "acme-wl-dev-plan@acme-admin-abcd.iam.gserviceaccount.com"
          apply = "acme-wl-dev-apply@acme-admin-abcd.iam.gserviceaccount.com"
        }
        # An env not in var.environments must be ignored, not granted.
        stale = {
          plan  = "acme-wl-stale-plan@acme-admin-abcd.iam.gserviceaccount.com"
          apply = "acme-wl-stale-apply@acme-admin-abcd.iam.gserviceaccount.com"
        }
      }
      workload_folder_roles = {
        plan  = ["organizations/123/roles/landingZonePlanViewer"]
        apply = ["roles/compute.admin"]
      }
      stage_service_accounts = {
        "network-hub" = {
          plan  = "acme-network-hub-plan@acme-admin-abcd.iam.gserviceaccount.com"
          apply = "acme-network-hub-apply@acme-admin-abcd.iam.gserviceaccount.com"
        }
      }
      network_folder_roles = {
        plan  = ["roles/compute.viewer"]
        apply = ["roles/compute.networkAdmin"]
      }
    }
  }
}

override_data {
  target = data.terraform_remote_state.gcp_organization
  values = {
    outputs = {
      billing_account = "000000-111111-222222"
      folders = {
        shared = { id = "folders/100", name = "folders/100", display_name = "Shared" }
        dev    = { id = "folders/111", name = "folders/111", display_name = "Development" }
      }
      tag_values = {
        "environment-dev" = "tagValues/123"
      }
    }
  }
}

run "workload_and_network_sas_get_folder_scoped_roles" {
  command = plan

  assert {
    condition = output.automation_folder_grants == {
      "dev|plan|organizations/123/roles/landingZonePlanViewer" = { folder = "folders/111", role = "organizations/123/roles/landingZonePlanViewer" }
      "dev|apply|roles/compute.admin"                          = { folder = "folders/111", role = "roles/compute.admin" }
      "network|plan|roles/compute.viewer"                      = { folder = "folders/100", role = "roles/compute.viewer" }
      "network|apply|roles/compute.networkAdmin"               = { folder = "folders/100", role = "roles/compute.networkAdmin" }
    }
    error_message = "Workload SAs must be granted only on their own env folder and network-hub SAs only on the shared folder; stale envs ignored."
  }
}

run "pre_c2_bootstrap_state_plans_without_grants" {
  command = plan

  override_data {
    target = data.terraform_remote_state.gcp_bootstrap
    values = {
      outputs = {
        admin_project_id = "acme-admin-abcd"
        suffix           = "abcd"
      }
    }
  }

  assert {
    condition     = output.automation_folder_grants == {}
    error_message = "A bootstrap state without the C2 outputs must plan cleanly with no automation grants."
  }
}

# "shared" is reserved for the hub/DNS projects; an environment with that key
# would silently replace them via merge().
run "rejects_reserved_shared_environment_key" {
  command = plan

  variables {
    environments = {
      shared = {
        display_name            = "Shared"
        cidr_block              = "10.99.0.0/16"
        region                  = "europe-west1"
        budget_monthly_limit    = 100
        iam_group_role_bindings = {}
      }
    }
  }

  expect_failures = [var.environments]
}
