# Services and service teams from config/landing-zone.yaml
# (gcp.environments.<env>.services / .service_teams). Precedence: explicit
# variable > config file > built-in default (empty). Remote-state reads are
# overridden; the host stage runs against mocks.

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

override_data {
  target = module.host.data.google_compute_zones.available
  values = {
    names = ["europe-west1-b", "europe-west1-c", "europe-west1-d"]
  }
}

run "services_from_config" {
  command = plan

  assert {
    condition     = join(",", sort(keys(local.app_services))) == "api,worker" && local.app_services["api"].min_instances == 1
    error_message = "gcp.environments.dev.services must populate the app services."
  }

  assert {
    condition     = join(",", keys(module.service_team)) == "payments" && local.service_teams["payments"].project_admin_group_email == "payments-admins@cfg.example" && local.service_teams["payments"].enable_shared_vpc_attachment
    error_message = "gcp.environments.dev.service_teams must create the team project, with the typed defaults applied."
  }
}

run "empty_services_section_is_noop" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.empty-services.yaml"
  }

  assert {
    condition     = length(local.app_services) == 0 && length(module.service_team) == 0
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
    condition     = join(",", keys(local.app_services)) == "only" && length(module.service_team) == 0
    error_message = "an explicit app_services / service_teams variable must win over the config file."
  }
}
