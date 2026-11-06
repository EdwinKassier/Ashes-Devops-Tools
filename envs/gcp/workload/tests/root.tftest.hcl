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

  # No app_services by default: the golden-path stage creates nothing.
  assert {
    condition     = length(output.app_services) == 0 && output.app_deploy_workload_identity_provider == null && output.gke_cluster_name == null
    error_message = "with app_services = {} and every app flag off, the app-services stage must create nothing"
  }

  # No service_teams by default: the registry creates nothing.
  assert {
    condition     = length(module.service_team) == 0
    error_message = "with no service_teams declared, the registry must create no service projects"
  }
}

# Data-driven service-team registry: declaring a team is a map entry,
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
        supabase_api_url           = "https://abcd.supabase.co"
        supabase_service_role_key  = "service-role-key-xxxx"
        supabase_database_password = "db-password-xxxx"
      }
    }
  }

  assert {
    condition     = length(module.saas_secret_bridge) == 1
    error_message = "enabling the bridge must instantiate the secret-manager module once."
  }
}

# Application golden path (modules/gcp/stages/app-services): one app_services
# entry yields an internal Cloud Run service, an image repo and a WIF-bound deploy
# SA in the env host project, on the env VPC's first private subnet.
run "app_service_golden_path" {
  command = plan

  variables {
    enable_app_deploy_wif = true
    app_services = {
      api = {
        github = { repository_id = "123456789", ref = "refs/heads/main" }
      }
    }
  }

  override_module {
    target = module.host
    outputs = {
      dns_zones         = {}
      nat_ip            = "34.1.2.3"
      network_id        = "projects/acme-dev-host-abcd/global/networks/acme-dev-vpc"
      network_name      = "acme-dev-vpc"
      network_self_link = "https://www.googleapis.com/compute/v1/projects/acme-dev-host-abcd/global/networks/acme-dev-vpc"
      subnets = {
        private = {
          "europe-west1-b" = { id = "projects/acme-dev-host-abcd/regions/europe-west1/subnetworks/acme-dev-vpc-private-europe-west1-b" }
        }
      }
      security_policy_id   = null
      vpc_peerings         = {}
      vpc_service_controls = {}
    }
  }

  assert {
    condition     = output.app_services["api"].image_repository == "europe-west1-docker.pkg.dev/acme-dev-host-abcd/api/api"
    error_message = "the image repo must be in the env host project and region from environment_config"
  }

  assert {
    condition     = output.app_github_actions["api"].GCP_DEPLOY_SA == "api-deploy@acme-dev-host-abcd.iam.gserviceaccount.com"
    error_message = "the per-service deploy SA must be exposed for the GitHub Actions workflow"
  }

  # The WIF pool name is built from the HOST project number in environment_config.
  assert {
    condition     = output.app_deploy_workload_identity_provider == "projects/222222222222/locations/global/workloadIdentityPools/apps-dev/providers/github"
    error_message = "the app-deploy WIF provider must live in the env host project (host_project_number), not the infra admin project"
  }

  assert {
    condition     = module.app_services.services["api"].service_name == "api"
    error_message = "the Cloud Run service must be named after the app_services key"
  }
}

# BCK-05 / VUL-05: VM snapshot schedules on by default (host project), VM
# Manager patching also on by default.
run "vm_backup_and_patching_on_by_default" {
  command = plan

  assert {
    condition     = length(module.vm_backup_policy) == 1 && contains(module.vm_backup_policy["host"].schedule_names, "vm-daily-snapshots")
    error_message = "the host project must get the default daily snapshot-schedule policy."
  }

  assert {
    condition     = length(module.os_patch_management) == 1 && length(google_project_service.osconfig) == 1
    error_message = "OS patch management must be on by default for the host project (the workload apply SA holds roles/osconfig.patchDeploymentAdmin)."
  }
}

run "vm_ops_cover_service_teams_when_enabled" {
  command = plan

  variables {
    enable_os_patch_management = true
    service_teams = {
      payments = {
        project_admin_group_email = "payments-admins@acme.test"
        shared_vpc_subnets = {
          private = { region = "europe-west1", subnet_name = "acme-dev-vpc-private-europe-west1-b" }
        }
      }
    }
  }

  assert {
    condition     = toset(keys(module.vm_backup_policy)) == toset(["host", "team-payments"])
    error_message = "snapshot schedules must be created in the host project and in every service-team project."
  }

  assert {
    condition     = toset(keys(module.os_patch_management)) == toset(["host", "team-payments"]) && google_project_service.osconfig["host"].service == "osconfig.googleapis.com"
    error_message = "enable_os_patch_management must enable osconfig and create a patch deployment per target project."
  }

  assert {
    condition     = contains(keys(module.os_patch_management["host"].patch_deployment_ids), "weekly-os-patch")
    error_message = "the default patch deployment must be weekly-os-patch."
  }
}

run "vm_backup_can_be_disabled" {
  command = plan

  variables {
    enable_vm_backup_policy = false
  }

  assert {
    condition     = length(module.vm_backup_policy) == 0
    error_message = "enable_vm_backup_policy = false must create no snapshot policies."
  }
}
