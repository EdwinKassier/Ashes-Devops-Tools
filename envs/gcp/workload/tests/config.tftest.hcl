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

# service_team = "<key>" resolves the service's project from the team module;
# a service without it stays in the host project.
run "service_team_resolves_service_project" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.team-service.yaml"
  }

  override_module {
    target = module.service_team["payments"]
    outputs = {
      project_id            = "payments-1a2b"
      project_number        = "333333333333"
      service_account_email = null
      subnet_iam_bindings   = {}
      host_project_id       = "cfgco-dev-host-abcd"
    }
  }

  assert {
    condition     = local.app_services["api"].project_id == "payments-1a2b" && local.app_services["api"].project_number == "333333333333" && local.app_services["api"].network_access_group == "payments"
    error_message = "service_team must resolve project_id / project_number from module.service_team and group the Shared VPC grants by team."
  }

  assert {
    condition     = local.app_services["api"].grant_network_access == true && !contains(keys(local.app_services["worker"]), "grant_network_access")
    error_message = "a service with service_team must be deployed into the team project (Shared VPC grants on); a service without must not."
  }

  assert {
    condition     = contains(local.team_service_apis["payments"], "run.googleapis.com") && contains(local.team_service_apis["payments"], "artifactregistry.googleapis.com") && contains(local.team_service_apis["payments"], "containerscanning.googleapis.com") && contains(local.team_service_apis["payments"], "monitoring.googleapis.com")
    error_message = "a team that hosts a service must have the Cloud Run and Artifact Registry APIs activated."
  }
}

run "service_without_team_stays_in_host_project" {
  command = plan

  assert {
    condition     = alltrue([for k, s in local.app_services : !contains(keys(s), "project_id")])
    error_message = "services without service_team must not carry a project_id (they deploy into the host project)."
  }

  assert {
    condition     = length(local.team_service_apis["payments"]) == 0
    error_message = "a team that hosts no service must not get extra APIs."
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
  }
}

run "scaffold_gcp_aws_plans" {
  command = plan

  variables {
    landing_zone_config_path = "../../../tests/fixtures/scaffold/landing-zone.gcp-aws.yaml"
    environment              = "dev"
  }
}

run "scaffold_gcp_aws_saas_plans" {
  command = plan

  variables {
    landing_zone_config_path = "../../../tests/fixtures/scaffold/landing-zone.gcp-aws-saas.yaml"
    environment              = "dev"
  }
}
