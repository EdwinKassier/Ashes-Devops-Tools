# Default-plan test for the gcp-workload root WITHOUT overriding the host stage.
#
# root.tftest.hcl overrides module.host, which hid a bug: with the default
# vpc_sc_access_policy_name = null the root still passed a perimeter to the host
# stage and the vpc-sc module's validation failed the plan. This suite runs the
# real host stage against mocks so a broken default plan cannot hide again.

mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  # Isolate the suite from any committed config/landing-zone.yaml.
  landing_zone_config_path = ""
  project_prefix           = "acme"
  environment              = "dev"
  tfc_organization         = "acme-tfc"
  monthly_budget_limit     = 0 # disable the budget module for this contract test
}

override_data {
  target = data.terraform_remote_state.organization
  values = {
    outputs = {
      org_id               = "123456789012"
      billing_account      = "billingAccounts/000000-111111-222222"
      admin_project_number = "111111111111"
      cmek_key_names       = {}
    }
  }
}

override_data {
  target = data.terraform_remote_state.projects
  values = {
    outputs = {
      environment_config = {
        dev = {
          folder_id           = "folders/111"
          folder_name         = "Development"
          host_project_id     = "acme-dev-host-abcd"
          host_project_number = "222222222222"
          region              = "europe-west1"
          cidr_block          = "10.10.0.0/16"
          labels              = {}
          tag_value_ids       = { environment = "tagValues/1" }
        }
      }
    }
  }
}

override_data {
  target = data.terraform_remote_state.network_hub
  values = {
    outputs = {
      hub_network = {
        vpc_self_link = "https://www.googleapis.com/compute/v1/projects/acme-hub/global/networks/hub-vpc"
        vpc_name      = "hub-vpc"
        dns_zone_name = "hub-dns"
        dns_domain    = "hub.internal."
      }
    }
  }
}

# The mock provider returns no zones, which trips the host stage's postcondition.
override_data {
  target = module.host.data.google_compute_zones.available
  values = {
    names = ["europe-west1-b", "europe-west1-c", "europe-west1-d"]
  }
}

run "default_plan_succeeds_without_vpc_sc" {
  command = plan

  assert {
    condition     = length(module.host.vpc_service_controls) == 0
    error_message = "with vpc_sc_access_policy_name = null the workload root must not create an environment perimeter"
  }
}

run "perimeter_created_when_access_policy_set" {
  command = plan

  variables {
    vpc_sc_access_policy_name = "1234567890"
  }

  assert {
    condition     = length(module.host.vpc_service_controls) == 1
    error_message = "setting vpc_sc_access_policy_name must create the environment perimeter"
  }
}

# SOTA M: an enforced perimeter can stage a dry-run delta (status + spec).
run "enforced_perimeter_stages_dry_run_delta" {
  command = plan

  variables {
    vpc_sc_access_policy_name          = "1234567890"
    vpc_sc_enable_dry_run              = false
    vpc_sc_dry_run_restricted_services = ["storage.googleapis.com", "bigquery.googleapis.com", "logging.googleapis.com"]
  }

  assert {
    condition     = module.host.vpc_service_controls["dev_perimeter"].enforced && module.host.vpc_service_controls["dev_perimeter"].dry_run_spec_staged
    error_message = "vpc_sc_dry_run_restricted_services on an enforced perimeter must keep status enforced AND stage a dry-run spec"
  }
}

# SOTA M: a production-like environment in dry-run (or with no perimeter) must
# raise the vpc_sc_enforced_in_prod check warning.
run "prod_without_enforced_perimeter_warns" {
  command = plan

  variables {
    environment = "prod"
  }

  override_data {
    target = data.terraform_remote_state.projects
    values = {
      outputs = {
        environment_config = {
          prod = {
            folder_id           = "folders/333"
            folder_name         = "Production"
            host_project_id     = "acme-prod-host-abcd"
            host_project_number = "333333333333"
            region              = "europe-west1"
            cidr_block          = "10.30.0.0/16"
            labels              = {}
            tag_value_ids       = { environment = "tagValues/3" }
          }
        }
      }
    }
  }

  expect_failures = [check.vpc_sc_enforced_in_prod]
}

# Application golden path against the REAL host stage: one app service lands on
# the env VPC's first private subnet, and Cloud SQL peers into the env VPC (where
# the host stage creates Private Service Access by default), not the hub.
run "app_service_on_real_host_stage" {
  command = plan

  variables {
    enable_app_deploy_wif = true
    app_services = {
      api = {
        database = {}
        github   = { repository_id = "123456789" }
      }
    }
  }

  assert {
    condition     = module.host.private_service_access_range_name == "google-managed-services"
    error_message = "the host stage must create Private Service Access on the env VPC by default (Cloud SQL private IP depends on it)."
  }

  assert {
    condition     = output.app_services["api"].runtime_service_account == "api-run@acme-dev-host-abcd.iam.gserviceaccount.com"
    error_message = "the app service must be created in the env host project."
  }

  assert {
    condition     = output.app_services["api"].database_iam_user == "api-run@acme-dev-host-abcd.iam"
    error_message = "the runtime SA must be the Cloud SQL IAM database user."
  }
}
