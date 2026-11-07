# Services and service teams from config/landing-zone.yaml
# (gcp.environments.<env>.services / .service_teams). Precedence: explicit
# variable > config file > built-in default (empty). Remote-state reads are
# overridden; the environment stage runs against mocks. How the stage resolves
# team projects and APIs is asserted in modules/gcp/stages/environment/tests.

mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  landing_zone_config_path = "tests/fixtures/landing-zone.services.yaml"
  environment              = "dev"
  monthly_budget_limit     = 0
  enable_network_hub       = false
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
            host_project_id     = "cfgco-dev-host-abcd"
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
}

override_data {
  target = module.environment.module.host.data.google_compute_zones.available
  values = {
    names = ["europe-west1-b", "europe-west1-c", "europe-west1-d"]
  }
}

run "services_from_config" {
  command = plan

  assert {
    condition     = join(",", sort(keys(local.app_services_input))) == "api,worker" && local.app_services_input["api"].min_instances == 1 && join(",", sort(keys(output.app_services))) == "api,worker"
    error_message = "gcp.environments.dev.services must populate the app services."
  }

  assert {
    condition     = join(",", module.environment.components.service_teams) == "payments" && local.service_teams["payments"].project_admin_group_email == "payments-admins@cfg.example" && local.service_teams["payments"].enable_shared_vpc_attachment
    error_message = "gcp.environments.dev.service_teams must create the team project, with the typed defaults applied."
  }
}

run "empty_services_section_is_noop" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.empty-services.yaml"
  }

  assert {
    condition     = length(local.app_services_input) == 0 && length(module.environment.components.service_teams) == 0
    error_message = "empty services / service_teams sections must create nothing."
  }
}

run "variable_overrides_config" {
  command = plan

  variables {
    app_services  = { only = {} }
    service_teams = {}
  }

  assert {
    condition     = join(",", keys(local.app_services_input)) == "only" && length(module.environment.components.service_teams) == 0
    error_message = "an explicit app_services / service_teams variable must win over the config file."
  }
}

# service_team = "<key>" in the config file reaches the environment stage, which
# resolves the service's project from the team module (asserted there).
run "service_team_resolves_service_project" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.team-service.yaml"
  }

  override_module {
    target = module.environment.module.service_team["payments"]
    outputs = {
      project_id            = "payments-1a2b"
      project_number        = "333333333333"
      service_account_email = null
      subnet_iam_bindings   = {}
      host_project_id       = "cfgco-dev-host-abcd"
    }
  }

  assert {
    condition     = local.app_services_input["api"].service_team == "payments" && !contains(keys(local.app_services_input["worker"]), "service_team") && module.environment.components.service_teams == ["payments"]
    error_message = "the config file's service_team must reach the environment stage, with the team declared."
  }

  assert {
    condition     = output.service_team_project_ids["payments"] == "payments-1a2b"
    error_message = "the team project must be the one the service_team module creates."
  }
}

run "service_without_team_stays_in_host_project" {
  command = plan

  assert {
    condition     = alltrue([for k, s in local.app_services_input : !contains(keys(s), "project_id") && !contains(keys(s), "service_team")])
    error_message = "services without service_team must not carry a project_id (they deploy into the host project)."
  }
}

run "unknown_service_team_is_rejected" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.unknown-team.yaml"
  }

  expect_failures = [var.app_services]
}

run "unknown_service_team_in_variable_is_rejected" {
  command = plan

  variables {
    app_services  = { api = { service_team = "ghost" } }
    service_teams = {}
  }

  expect_failures = [var.app_services]
}

run "service_team_and_project_id_are_exclusive" {
  command = plan

  variables {
    app_services  = { api = { service_team = "payments", project_id = "x-12345" } }
    service_teams = { payments = { project_admin_group_email = "p@cfg.example", shared_vpc_subnets = { a = { region = "europe-west1", subnet_name = "s" } } } }
  }

  expect_failures = [var.app_services]
}

# Scaffold matrix: committed scaffolder output (make scaffold-fixtures) must plan.
run "scaffold_gcp_plans" {
  command = plan

  variables {
    landing_zone_config_path = "../../../tests/fixtures/scaffold/landing-zone.gcp.yaml"
    environment              = "dev"
    # Undo the file-level standalone/no-budget settings so the budget module
    # (operator-chosen limit; the root takes it from a variable, not config)
    # and the hub wiring (remote-state contract below) are planned.
    monthly_budget_limit = 1000
    enable_network_hub   = true
  }

  # google_billing_account.id is the bare XXXXXX-XXXXXX-XXXXXX form, which the
  # budget module requires (the file-level override uses the name form).
  override_data {
    target = data.terraform_remote_state.organization
    values = {
      outputs = {
        contract = {
          org_id               = "123456789012"
          billing_account      = "000000-111111-222222"
          admin_project_number = "111111111111"
          cmek_key_names       = {}
        }
      }
    }
  }

  override_data {
    target = data.terraform_remote_state.network_hub[0]
    values = {
      outputs = {
        contract = {
          hub_network = {
            vpc_self_link = "https://www.googleapis.com/compute/v1/projects/acme-hub-abcd/global/networks/acme-hub-vpc"
            dns_domain    = "hub.internal."
          }
        }
      }
    }
  }

  assert {
    condition     = module.environment.components.budget && local.read_network_hub
    error_message = "the scaffold runs must plan the budget module and read the network-hub remote state."
  }
}

run "scaffold_gcp_aws_plans" {
  command = plan

  variables {
    landing_zone_config_path = "../../../tests/fixtures/scaffold/landing-zone.gcp-aws.yaml"
    environment              = "dev"
    # Undo the file-level standalone/no-budget settings so the budget module
    # (operator-chosen limit; the root takes it from a variable, not config)
    # and the hub wiring (remote-state contract below) are planned.
    monthly_budget_limit = 1000
    enable_network_hub   = true
  }

  # google_billing_account.id is the bare XXXXXX-XXXXXX-XXXXXX form, which the
  # budget module requires (the file-level override uses the name form).
  override_data {
    target = data.terraform_remote_state.organization
    values = {
      outputs = {
        contract = {
          org_id               = "123456789012"
          billing_account      = "000000-111111-222222"
          admin_project_number = "111111111111"
          cmek_key_names       = {}
        }
      }
    }
  }

  override_data {
    target = data.terraform_remote_state.network_hub[0]
    values = {
      outputs = {
        contract = {
          hub_network = {
            vpc_self_link = "https://www.googleapis.com/compute/v1/projects/acme-hub-abcd/global/networks/acme-hub-vpc"
            dns_domain    = "hub.internal."
          }
        }
      }
    }
  }

  assert {
    condition     = module.environment.components.budget && local.read_network_hub
    error_message = "the scaffold runs must plan the budget module and read the network-hub remote state."
  }
}

run "scaffold_gcp_aws_saas_plans" {
  command = plan

  variables {
    landing_zone_config_path = "../../../tests/fixtures/scaffold/landing-zone.gcp-aws-saas.yaml"
    environment              = "dev"
    # Undo the file-level standalone/no-budget settings so the budget module
    # (operator-chosen limit; the root takes it from a variable, not config)
    # and the hub wiring (remote-state contract below) are planned.
    monthly_budget_limit = 1000
    enable_network_hub   = true
  }

  # google_billing_account.id is the bare XXXXXX-XXXXXX-XXXXXX form, which the
  # budget module requires (the file-level override uses the name form).
  override_data {
    target = data.terraform_remote_state.organization
    values = {
      outputs = {
        contract = {
          org_id               = "123456789012"
          billing_account      = "000000-111111-222222"
          admin_project_number = "111111111111"
          cmek_key_names       = {}
        }
      }
    }
  }

  override_data {
    target = data.terraform_remote_state.network_hub[0]
    values = {
      outputs = {
        contract = {
          hub_network = {
            vpc_self_link = "https://www.googleapis.com/compute/v1/projects/acme-hub-abcd/global/networks/acme-hub-vpc"
            dns_domain    = "hub.internal."
          }
        }
      }
    }
  }

  assert {
    condition     = module.environment.components.budget && local.read_network_hub
    error_message = "the scaffold runs must plan the budget module and read the network-hub remote state."
  }
}
