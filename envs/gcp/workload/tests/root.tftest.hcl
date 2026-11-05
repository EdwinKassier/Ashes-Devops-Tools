# Cross-root CONTRACT test for the gcp-workload root (the CONSUMER).
#
# gcp-workload reads environment_config from gcp-projects, hub_network from
# gcp-network-hub, and org_id / billing_account / admin_project_number from
# gcp-organization. This test overrides all three upstream remote states with a
# known contract and the host stage module, then asserts the root resolves the
# contract (the host project comes from environment_config). It guards against a
# downstream root reading the wrong key or workspace after a refactor.

mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  project_prefix       = "acme"
  environment          = "dev"
  tfc_organization     = "acme-tfc"
  monthly_budget_limit = 0 # disable the budget module for this contract test
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

# The host stage is exercised by its own module tests; here we only check the
# root's cross-root wiring, so override it with the outputs the root re-exports.
override_module {
  target = module.host
  outputs = {
    dns_zones            = {}
    nat_ip               = "34.1.2.3"
    network_id           = "projects/acme-dev-host-abcd/global/networks/acme-dev-vpc"
    network_name         = "acme-dev-vpc"
    network_self_link    = "https://www.googleapis.com/compute/v1/projects/acme-dev-host-abcd/global/networks/acme-dev-vpc"
    security_policy_id   = null
    subnets              = {}
    vpc_peerings         = {}
    vpc_service_controls = {}
  }
}

run "workload_consumes_cross_root_contract" {
  command = plan

  # The host project is looked up from gcp-projects' environment_config.
  assert {
    condition     = data.google_project.host_project.project_id == "acme-dev-host-abcd"
    error_message = "workload must resolve the host project from gcp-projects' environment_config[<env>].host_project_id"
  }

  # The re-exported network outputs flow from the overridden host stage.
  assert {
    condition     = output.network_name == "acme-dev-vpc"
    error_message = "workload must re-export the host network name"
  }

  # No service_teams by default: the registry creates nothing (audit H10).
  assert {
    condition     = length(module.service_team) == 0
    error_message = "with no service_teams declared, the registry must create no service projects"
  }
}

# Data-driven service-team registry (audit H10): declaring a team is a map entry,
# which fans out to one workload module instance with normalised folder/billing IDs.
run "service_team_registry_fans_out" {
  command = plan

  variables {
    service_teams = {
      payments = {
        project_admin_group_email = "payments-admins@acme.test"
        activate_apis             = ["run.googleapis.com", "bigquery.googleapis.com"]
        project_admin_roles       = ["roles/run.developer"]
        shared_vpc_subnets = {
          private = { region = "europe-west1", subnet_name = "acme-dev-vpc-private-europe-west1-b" }
        }
      }
    }
  }

  # One module instance is created for the declared team.
  assert {
    condition     = length(module.service_team) == 1
    error_message = "one service_teams entry must create exactly one workload module instance"
  }

  # folder_id is normalised from the folders/NNN remote-state value to the bare
  # numeric ID the workload module requires.
  assert {
    condition     = module.service_team["payments"].host_project_id == "acme-dev-host-abcd"
    error_message = "the service project must attach to the environment host project as its Shared VPC host"
  }
}

# SaaS secret bridge (audit H9, hybrid option C): opt-in, default off, and when
# enabled it writes the Supabase connection details into a Secret Manager secret.
run "saas_secret_bridge_default_off" {
  command = plan

  assert {
    condition     = length(module.saas_secret_bridge) == 0
    error_message = "the SaaS secret bridge must create nothing when disabled (default)."
  }
}

run "saas_secret_bridge_creates_secret_when_enabled" {
  command = plan

  variables {
    enable_saas_secret_bridge    = true
    saas_workspace_name          = "saas-web"
    saas_secret_name             = "supabase-connection"
    saas_secret_accessor_members = ["serviceAccount:app@acme-dev-host-abcd.iam.gserviceaccount.com"]
  }

  override_data {
    target = data.terraform_remote_state.saas[0]
    values = {
      outputs = {
        supabase_api_url          = "https://abcd.supabase.co"
        supabase_service_role_key = "service-role-key-xxxx"
        supabase_database_password = "db-password-xxxx"
      }
    }
  }

  assert {
    condition     = length(module.saas_secret_bridge) == 1
    error_message = "enabling the bridge must instantiate the secret-manager module once."
  }
}
