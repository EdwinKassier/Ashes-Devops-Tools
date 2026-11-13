# Default-plan test for the gcp-workload root WITHOUT overriding the spoke network.
#
# root.tftest.hcl overrides module.environment.module.host, which hid a bug: with
# the default vpc_sc_access_policy_name = null the root still passed a perimeter
# to the spoke and the vpc-sc module's validation failed the plan. This suite runs
# the real environment stage against mocks so a broken default plan cannot hide
# again.

# A planned peering's state is unknown, which leaves check.hub_peering_active
# unknown, and terraform test fails a plan run on an unknown check (a real plan
# only warns). ACTIVE is what a peered environment reports.
mock_provider "google" {
  mock_resource "google_compute_network_peering" {
    override_during = plan
    defaults = {
      state = "ACTIVE"
    }
  }
}
mock_provider "google-beta" {}
# tfe serves only the SaaS secret bridge (ephemeral "tfe_outputs"); mocked so
# no run contacts HCP Terraform.
mock_provider "tfe" {}

variables {
  # Isolate the suite from any committed config/landing-zone.yaml.
  landing_zone_config_path = ""
  project_prefix           = "acme"
  environment              = "dev"
  tfc_organization         = "acme-tfc"
  monthly_budget_limit     = 0 # disable the budget module for this contract test
  # Production needs pinned zones (IAC-1); the runs below that test the
  # requirement unset it.
  zones = ["europe-west1-b", "europe-west1-c", "europe-west1-d"]
}

override_data {
  target = data.terraform_remote_state.organization
  values = {
    outputs = {
      contract = {
        org_id               = "123456789012"
        billing_account      = "billingAccounts/000000-111111-222222"
        admin_project_number = "111111111111"
        cmek_key_names       = {}
      }
    }
  }
}

override_data {
  target = data.terraform_remote_state.projects
  values = {
    outputs = {
      contract = {
        environment_config = {
          dev = {
            folder_id           = "folders/111"
            folder_name         = "Development"
            host_project_id     = "acme-dev-host-abcd"
            host_project_number = "222222222222"
            is_production       = false
            region              = "europe-west1"
            cidr_block          = "10.10.0.0/16"
            labels              = {}
            tag_value_ids       = { environment = "tagValues/1" }
          }
        }
      }
    }
  }
}

override_data {
  target = data.terraform_remote_state.network_hub
  values = {
    outputs = {
      contract = {
        hub_network = {
          vpc_self_link = "https://www.googleapis.com/compute/v1/projects/acme-hub/global/networks/hub-vpc"
          vpc_name      = "hub-vpc"
          dns_zone_name = "hub-dns"
          dns_domain    = "hub.internal."
        }
      }
    }
  }
}

# The mock provider returns no zones, which trips the spoke network's postcondition.
override_data {
  target = module.environment.module.host.data.google_compute_zones.available
  values = {
    names = ["europe-west1-b", "europe-west1-c", "europe-west1-d"]
  }
}

run "default_plan_succeeds_without_vpc_sc" {
  command = plan

  assert {
    condition     = length(module.environment.components.vpc_sc_perimeters) == 0 && output.vpc_sc_perimeter_names == {}
    error_message = "with vpc_sc_access_policy_name = null the workload root must not create an environment perimeter"
  }
}

run "perimeter_created_when_access_policy_set" {
  command = plan

  variables {
    vpc_sc_access_policy_name = "1234567890"
  }

  assert {
    condition     = module.environment.components.vpc_sc_perimeters == ["dev_perimeter"]
    error_message = "setting vpc_sc_access_policy_name must create the environment perimeter"
  }

  # Dry-run perimeter: keep all-apis until the perimeter is enforced.
  assert {
    condition     = module.environment.components.psc_target == "all-apis"
    error_message = "a dry-run perimeter must keep the all-apis PSC bundle."
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

  # Enforced perimeter: Google APIs through the restricted (vpc-sc) bundle.
  assert {
    condition     = module.environment.components.psc_target == "vpc-sc"
    error_message = "an enforced perimeter must switch the PSC endpoint to the vpc-sc bundle."
  }
}

# SEC-8: a production environment in dry-run (or with no perimeter) fails the
# plan unless production_vpc_sc_dry_run_waiver names a reason and a future expiry.
run "prod_without_enforced_perimeter_fails" {
  command = plan

  variables {
    environment = "prod"
  }

  override_data {
    target = data.terraform_remote_state.projects
    values = {
      outputs = {
        contract = {
          environment_config = {
            prod = {
              folder_id           = "folders/333"
              folder_name         = "Production"
              host_project_id     = "acme-prod-host-abcd"
              host_project_number = "333333333333"
              is_production       = true
              region              = "europe-west1"
              cidr_block          = "10.30.0.0/16"
              labels              = {}
              tag_value_ids       = { environment = "tagValues/3" }
            }
          }
        }
      }
    }
  }

  expect_failures = [terraform_data.production_vpc_sc_enforced]
}

# A waiver with a reason and a future expiry lets a first production rollout
# plan in dry-run. The guard resource still exists.
run "prod_dry_run_waiver_allows_plan" {
  command = plan

  variables {
    environment = "prod"
    production_vpc_sc_dry_run_waiver = {
      reason  = "First rollout: reading the dry-run violation logs before enforcing."
      expires = "2099-12-31"
    }
  }

  override_data {
    target = data.terraform_remote_state.projects
    values = {
      outputs = {
        contract = {
          environment_config = {
            prod = {
              folder_id           = "folders/333"
              folder_name         = "Production"
              host_project_id     = "acme-prod-host-abcd"
              host_project_number = "333333333333"
              is_production       = true
              region              = "europe-west1"
              cidr_block          = "10.30.0.0/16"
              labels              = {}
              tag_value_ids       = { environment = "tagValues/3" }
            }
          }
        }
      }
    }
  }

  assert {
    condition     = length(terraform_data.production_vpc_sc_enforced) == 1
    error_message = "the waiver lets the plan through; the precondition resource still exists."
  }
}

# A waiver past its expiry date no longer waives: the plan fails again.
run "prod_expired_waiver_fails" {
  command = plan

  variables {
    environment = "prod"
    production_vpc_sc_dry_run_waiver = {
      reason  = "First rollout: reading the dry-run violation logs before enforcing."
      expires = "2020-01-31"
    }
  }

  override_data {
    target = data.terraform_remote_state.projects
    values = {
      outputs = {
        contract = {
          environment_config = {
            prod = {
              folder_id           = "folders/333"
              folder_name         = "Production"
              host_project_id     = "acme-prod-host-abcd"
              host_project_number = "333333333333"
              is_production       = true
              region              = "europe-west1"
              cidr_block          = "10.30.0.0/16"
              labels              = {}
              tag_value_ids       = { environment = "tagValues/3" }
            }
          }
        }
      }
    }
  }

  expect_failures = [terraform_data.production_vpc_sc_enforced]
}

# An enforced production perimeter needs no waiver.
run "prod_enforced_perimeter_plans" {
  command = plan

  variables {
    environment               = "prod"
    vpc_sc_access_policy_name = "1234567890"
    vpc_sc_enable_dry_run     = false
  }

  override_data {
    target = data.terraform_remote_state.projects
    values = {
      outputs = {
        contract = {
          environment_config = {
            prod = {
              folder_id           = "folders/333"
              folder_name         = "Production"
              host_project_id     = "acme-prod-host-abcd"
              host_project_number = "333333333333"
              is_production       = true
              region              = "europe-west1"
              cidr_block          = "10.30.0.0/16"
              labels              = {}
              tag_value_ids       = { environment = "tagValues/3" }
            }
          }
        }
      }
    }
  }

  assert {
    condition     = length(terraform_data.production_vpc_sc_enforced) == 1
    error_message = "an enforced production perimeter must plan without a waiver."
  }
}

# A non-production environment has no guard at all.
run "non_production_has_no_perimeter_guard" {
  command = plan

  assert {
    condition     = length(terraform_data.production_vpc_sc_enforced) == 0
    error_message = "the production perimeter guard must not exist for a non-production environment."
  }
}

# IAC-1: a production environment must pin its zones, or a change in the zones
# GCP returns would re-derive the subnet CIDRs and replace in-use subnets.
run "prod_without_pinned_zones_fails" {
  command = plan

  variables {
    environment               = "prod"
    zones                     = null
    vpc_sc_access_policy_name = "1234567890"
    vpc_sc_enable_dry_run     = false
  }

  override_data {
    target = data.terraform_remote_state.projects
    values = {
      outputs = {
        contract = {
          environment_config = {
            prod = {
              folder_id           = "folders/333"
              folder_name         = "Production"
              host_project_id     = "acme-prod-host-abcd"
              host_project_number = "333333333333"
              is_production       = true
              region              = "europe-west1"
              cidr_block          = "10.30.0.0/16"
              labels              = {}
              tag_value_ids       = { environment = "tagValues/3" }
            }
          }
        }
      }
    }
  }

  expect_failures = [terraform_data.production_network_guard]
}

# gcp.environments.<env>.zones pins the spoke's zones in the given order.
run "prod_zones_from_config" {
  command = plan

  variables {
    landing_zone_config_path  = "tests/fixtures/landing-zone-zones.yaml"
    environment               = "prod"
    zones                     = null
    vpc_sc_access_policy_name = "1234567890"
    vpc_sc_enable_dry_run     = false
  }

  override_data {
    target = data.terraform_remote_state.projects
    values = {
      outputs = {
        contract = {
          environment_config = {
            prod = {
              folder_id           = "folders/333"
              folder_name         = "Production"
              host_project_id     = "acme-prod-host-abcd"
              host_project_number = "333333333333"
              is_production       = true
              region              = "europe-west1"
              cidr_block          = "10.30.0.0/16"
              labels              = {}
              tag_value_ids       = { environment = "tagValues/3" }
            }
          }
        }
      }
    }
  }

  assert {
    condition     = join(",", local.zones) == "europe-west1-d,europe-west1-b" && length(terraform_data.production_network_guard) == 1
    error_message = "gcp.environments.prod.zones must set the spoke's zones, in order, and satisfy the production guard."
  }

  assert {
    condition     = module.environment.subnets.private["europe-west1-d"].ip_cidr_range == "10.30.16.0/24" && module.environment.subnets.private["europe-west1-b"].ip_cidr_range == "10.30.17.0/24" && length(module.environment.subnets.private) == 2
    error_message = "The first pinned zone must take the first private CIDR, and no discovered zone may add a subnet."
  }
}

# An explicit zones variable wins over the config file.
run "zones_variable_beats_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-zones.yaml"
    zones                    = ["europe-west1-c"]
  }

  assert {
    condition     = join(",", local.zones) == "europe-west1-c"
    error_message = "The zones variable must win over gcp.environments.<env>.zones."
  }
}

run "rejects_malformed_zone" {
  command = plan

  variables {
    zones = ["europe-west1"]
  }

  expect_failures = [var.zones]
}

run "rejects_waiver_without_reason" {
  command = plan

  variables {
    production_vpc_sc_dry_run_waiver = { reason = " ", expires = "2099-12-31" }
  }

  expect_failures = [var.production_vpc_sc_dry_run_waiver]
}

run "rejects_waiver_with_malformed_expiry" {
  command = plan

  variables {
    production_vpc_sc_dry_run_waiver = { reason = "First rollout.", expires = "2099-02-30" }
  }

  expect_failures = [var.production_vpc_sc_dry_run_waiver]
}

# Application golden path against the REAL environment stage: the app service
# lands in the env host project (the Private Service Access and subnet wiring is
# asserted in the environment stage's plan suite).
run "app_service_on_real_host_stage" {
  command = plan

  variables {
    enable_app_deploy_wif      = true
    github_repository_owner_id = "42"
    app_services = {
      api = {
        database = {}
        github   = { repository_id = "123456789" }
      }
    }
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

# The spoke VPC takes the name gcp-projects publishes (the name gcp-network-hub
# peers with), not a second derivation in this root (ARC-5).
run "spoke_network_name_from_projects_contract" {
  command = plan

  override_data {
    target = data.terraform_remote_state.projects
    values = {
      outputs = {
        contract = {
          environment_config = {
            dev = {
              folder_id           = "folders/111"
              folder_name         = "Development"
              host_project_id     = "acme-dev-host-abcd"
              host_project_number = "222222222222"
              is_production       = false
              region              = "europe-west1"
              cidr_block          = "10.10.0.0/16"
              labels              = {}
              tag_value_ids       = { environment = "tagValues/1" }
              spoke_network_name  = "acme-dev-custom-vpc"
            }
          }
        }
      }
    }
  }

  assert {
    condition     = output.network_name == "acme-dev-custom-vpc"
    error_message = "The spoke VPC must use environment_config.<env>.spoke_network_name from the gcp-projects contract."
  }
}

# A gcp-projects state from before spoke_network_name keeps the old name.
run "spoke_network_name_falls_back_without_contract_key" {
  command = plan

  assert {
    condition     = output.network_name == "acme-dev-vpc"
    error_message = "Without spoke_network_name the spoke VPC stays <project_prefix>-<environment>-vpc."
  }
}
