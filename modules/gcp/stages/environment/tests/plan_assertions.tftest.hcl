# Plan assertions for stages/environment: the composition behind every
# gcp-workload-<env> workspace. Mock providers, no credentials. The root's
# config, contract and wiring coverage stays in envs/gcp/workload/tests.

mock_provider "google" {
  mock_data "google_compute_zones" {
    defaults = {
      names = ["europe-west1-b", "europe-west1-c", "europe-west1-d"]
    }
  }
  mock_data "google_project" {
    defaults = {
      number = "222222222222"
    }
  }
}
mock_provider "google-beta" {}

variables {
  environment          = "dev"
  project_prefix       = "acme"
  org_id               = "123456789012"
  billing_account      = "billingAccounts/000000-111111-222222"
  admin_project_number = "111111111111"
  labels               = { environment = "dev", managed-by = "terraform" }

  host_project = {
    project_id     = "acme-dev-host-abcd"
    project_number = "222222222222"
    folder_id      = "folders/111"
    region         = "europe-west1"
    cidr_block     = "10.10.0.0/16"
  }
}

run "defaults_create_spoke_and_vm_operations_only" {
  command = plan

  assert {
    condition     = output.network_name == "acme-dev-vpc" && module.host.private_service_access_range_name == "google-managed-services"
    error_message = "The spoke VPC is <prefix>-<env>-vpc with Private Service Access on by default (Cloud SQL private IP depends on it)."
  }

  assert {
    condition = (
      !output.components.budget && !output.components.cloud_armor && !output.components.saas_secret_bridge &&
      length(output.components.vpc_sc_perimeters) == 0 && length(output.components.service_teams) == 0 &&
      length(output.components.public_ingress) == 0 && length(output.app_services) == 0
    )
    error_message = "With every opt-in off the environment creates no budget, Cloud Armor, perimeter, team, bridge, app service or ingress."
  }

  assert {
    condition     = output.components.psc_target == "all-apis"
    error_message = "Without an enforced perimeter the PSC endpoint keeps the all-apis bundle."
  }

  # BCK-05 / VUL-05: snapshot schedules and VM Manager patching on by default.
  assert {
    condition     = output.components.vm_backup_targets == ["host"] && contains(module.vm_backup_policy["host"].schedule_names, "vm-daily-snapshots")
    error_message = "The host project must get the default daily snapshot-schedule policy."
  }

  assert {
    condition     = output.components.os_patch_targets == ["host"] && google_project_service.osconfig["host"].service == "osconfig.googleapis.com" && !google_project_service.osconfig["host"].disable_on_destroy
    error_message = "OS patch management must be on by default for the host project, with osconfig enabled and kept on destroy."
  }

  assert {
    condition     = contains(keys(module.os_patch_management["host"].patch_deployment_ids), "weekly-os-patch")
    error_message = "The default patch deployment must be weekly-os-patch."
  }
}

run "budget_targets_the_host_project" {
  command = plan

  variables {
    billing_account = "000000-111111-222222"
    budget          = { monthly_limit = 1000, currency = "EUR" }
  }

  assert {
    condition     = output.components.budget && module.budget[0].budget_amount.amount == 1000 && module.budget[0].budget_amount.currency == "EUR"
    error_message = "A positive monthly_limit must create the budget with that amount."
  }
}

run "perimeter_with_default_policies" {
  command = plan

  variables {
    vpc_service_controls = { access_policy_name = "1234567890" }
  }

  assert {
    condition     = output.components.vpc_sc_perimeters == ["dev_perimeter"]
    error_message = "An access policy must create the <env>_perimeter perimeter."
  }

  assert {
    condition = (
      local.effective_vpc_sc_ingress_policies[0].sources[0].resource == "//iam.googleapis.com/projects/111111111111/locations/global/workloadIdentityPools/*" &&
      local.effective_vpc_sc_egress_policies[0].operations[0].service_name == "storage.googleapis.com"
    )
    error_message = "Empty policy lists must use the defaults: admin-project WIF pools in, storage out."
  }

  assert {
    condition     = output.components.psc_target == "all-apis"
    error_message = "A dry-run perimeter must keep the all-apis PSC bundle."
  }
}

# An enforced perimeter can stage a dry-run delta (status + spec).
run "enforced_perimeter_stages_dry_run_delta" {
  command = plan

  variables {
    vpc_service_controls = {
      access_policy_name          = "1234567890"
      enable_dry_run              = false
      dry_run_restricted_services = ["storage.googleapis.com", "bigquery.googleapis.com", "logging.googleapis.com"]
    }
  }

  assert {
    condition     = module.host.vpc_service_controls["dev_perimeter"].enforced && module.host.vpc_service_controls["dev_perimeter"].dry_run_spec_staged
    error_message = "dry_run_restricted_services on an enforced perimeter must keep status enforced AND stage a dry-run spec."
  }

  assert {
    condition     = output.components.psc_target == "vpc-sc"
    error_message = "An enforced perimeter must switch the PSC endpoint to the vpc-sc bundle."
  }
}

run "explicit_psc_target_wins" {
  command = plan

  variables {
    network              = { private_service_connect_target = "all-apis" }
    vpc_service_controls = { access_policy_name = "1234567890", enable_dry_run = false }
  }

  assert {
    condition     = output.components.psc_target == "all-apis"
    error_message = "An explicit private_service_connect_target must win over the derived one."
  }
}

run "hub_ncc_connectivity_passes_through" {
  command = plan

  variables {
    hub = {
      connectivity = "ncc"
      ncc          = { hub_id = "projects/acme-hub/locations/global/hubs/acme-ncc-hub", group = "default" }
      peerings = {
        "hub-peering" = {
          peer_network         = "https://www.googleapis.com/compute/v1/projects/acme-hub/global/networks/hub-vpc"
          export_custom_routes = true
          import_custom_routes = true
        }
      }
      dns_zones = {
        "internal-peering" = {
          dns_name        = "hub.internal."
          visibility      = "private"
          peering_network = "https://www.googleapis.com/compute/v1/projects/acme-hub/global/networks/hub-vpc"
          dnssec_enabled  = true
        }
      }
    }
  }

  assert {
    condition     = length(output.vpc_peerings) == 0 && contains(keys(output.dns_zones), "internal-peering")
    error_message = "connectivity = ncc must drop the hub VPC peering and keep the hub DNS peering zone."
  }
}

# Service team registry: folder/billing normalised, attached to the host project.
run "service_team_registry_fans_out" {
  command = plan

  variables {
    service_teams = {
      payments = {
        project_admin_group_email = "payments-admins@acme.test"
        activate_apis             = ["bigquery.googleapis.com"]
        shared_vpc_subnets = {
          private = { region = "europe-west1", subnet_name = "acme-dev-vpc-private-europe-west1-b" }
        }
      }
    }
  }

  assert {
    condition     = output.components.service_teams == ["payments"] && module.service_team["payments"].host_project_id == "acme-dev-host-abcd"
    error_message = "One team entry must create one service project attached to the environment host project."
  }

  assert {
    condition     = toset(output.components.vm_backup_targets) == toset(["host", "team-payments"]) && toset(output.components.os_patch_targets) == toset(["host", "team-payments"])
    error_message = "Snapshot schedules and patch deployments must cover the host project and every service-team project."
  }

  assert {
    condition     = length(local.team_service_apis["payments"]) == 0
    error_message = "A team that hosts no service must not get extra APIs."
  }
}

# service_team = "<key>": the service's project comes from the team module.
run "service_team_resolves_service_project" {
  command = plan

  variables {
    service_teams = {
      payments = {
        project_admin_group_email = "payments-admins@acme.test"
        shared_vpc_subnets = {
          private = { region = "europe-west1", subnet_name = "acme-dev-vpc-private-europe-west1-b" }
        }
      }
    }
    app_services = {
      api    = { service_team = "payments", database = {} }
      worker = {}
    }
  }

  override_module {
    target = module.service_team["payments"]
    outputs = {
      project_id            = "payments-1a2b"
      project_number        = "333333333333"
      service_account_email = null
      subnet_iam_bindings   = {}
      host_project_id       = "acme-dev-host-abcd"
    }
  }

  assert {
    condition     = local.app_services["api"].project_id == "payments-1a2b" && local.app_services["api"].project_number == "333333333333" && local.app_services["api"].network_access_group == "payments"
    error_message = "service_team must resolve project_id / project_number from module.service_team and group the Shared VPC grants by team."
  }

  assert {
    condition     = local.app_services["api"].grant_network_access == true && !contains(keys(local.app_services["worker"]), "grant_network_access") && !contains(keys(local.app_services["worker"]), "project_id")
    error_message = "A service with service_team is deployed into the team project (Shared VPC grants on); a service without stays in the host project."
  }

  assert {
    condition = alltrue([
      for api in ["run.googleapis.com", "artifactregistry.googleapis.com", "iam.googleapis.com", "containerscanning.googleapis.com", "monitoring.googleapis.com", "sqladmin.googleapis.com"] :
      contains(local.team_service_apis["payments"], api)
    ])
    error_message = "A team that hosts a service (with a database) must have the Cloud Run, Artifact Registry and Cloud SQL APIs activated."
  }
}

# Application golden path on the real spoke: host project, first private subnet,
# Cloud SQL IAM user.
run "app_service_on_real_spoke" {
  command = plan

  variables {
    app_platform = {
      enable_deploy_wif          = true
      github_repository_owner_id = "42"
    }
    app_services = {
      api = {
        database = {}
        github   = { repository_id = "123456789" }
      }
    }
  }

  assert {
    condition     = output.app_services["api"].runtime_service_account == "api-run@acme-dev-host-abcd.iam.gserviceaccount.com" && output.app_services["api"].database_iam_user == "api-run@acme-dev-host-abcd.iam"
    error_message = "The app service must be created in the env host project, its runtime SA the Cloud SQL IAM user."
  }

  assert {
    condition     = output.app_deploy_workload_identity_provider == "projects/222222222222/locations/global/workloadIdentityPools/apps-dev/providers/github"
    error_message = "The app-deploy WIF provider must live in the env host project (host_project.project_number)."
  }

  assert {
    condition     = output.app_services["api"].initial_image == "us-docker.pkg.dev/cloudrun/container/hello"
    error_message = "The first revision defaults to the public Cloud Run sample."
  }
}

run "public_ingress_switches_exposed_services" {
  command = plan

  variables {
    cloud_armor    = { enabled = true }
    app_services   = { api = {}, worker = {} }
    public_ingress = { api = { domains = ["api.dev.acme.example"] } }
  }

  assert {
    condition     = output.components.public_ingress == ["api"] && one(module.app_ingress["api"].managed_domains) == "api.dev.acme.example"
    error_message = "Only the listed service is exposed, with a managed certificate for its domains."
  }

  assert {
    condition     = output.components.cloud_armor
    error_message = "cloud_armor.enabled must create the environment Cloud Armor policy."
  }

  assert {
    condition = (
      local.app_services["api"].ingress == "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER" &&
      local.app_services["api"].enable_unauthenticated &&
      local.app_services["worker"].ingress == "INGRESS_TRAFFIC_INTERNAL_ONLY" &&
      !local.app_services["worker"].enable_unauthenticated
    )
    error_message = "Exposed services switch to LB-only ingress; the rest stay internal."
  }
}

# Applied (mocked) so the load balancer's computed IDs are concrete.
run "public_ingress_backend_and_neg_exist" {
  command = apply

  variables {
    app_services   = { api = {} }
    public_ingress = { api = { domains = ["api.dev.acme.example"] } }
    vm_operations  = { enable_backup_policy = false, enable_os_patch_management = false }
  }

  override_module {
    target = module.host
    outputs = {
      dns_zones                 = {}
      nat_ip                    = "34.1.2.3"
      network_id                = "projects/acme-dev-host-abcd/global/networks/acme-dev-vpc"
      network_name              = "acme-dev-vpc"
      network_self_link         = "https://www.googleapis.com/compute/v1/projects/acme-dev-host-abcd/global/networks/acme-dev-vpc"
      security_policy_id        = "projects/acme-dev-host-abcd/global/securityPolicies/acme-dev-armor"
      security_policy_self_link = "https://www.googleapis.com/compute/v1/projects/acme-dev-host-abcd/global/securityPolicies/acme-dev-armor"
      subnets                   = {}
      vpc_peerings              = {}
      vpc_service_controls      = {}
    }
  }

  override_module {
    target = module.app_services
    outputs = {
      services                   = { api = { service_name = "api", initial_image = "us-docker.pkg.dev/cloudrun/container/hello" } }
      workload_identity_provider = null
      github_actions             = {}
      gke_cluster_name           = null
    }
  }

  assert {
    condition     = module.app_ingress["api"].backend_service_id != null && module.app_ingress["api"].https_forwarding_rule_id != null
    error_message = "Public ingress must create the backend service and HTTPS forwarding rule."
  }

  assert {
    condition     = output.public_ingress["api"].ip_address != null
    error_message = "The load balancer IP must be exposed for DNS."
  }
}

run "saas_secret_bridge_when_enabled" {
  command = plan

  variables {
    saas_secret_bridge = {
      enabled          = true
      accessor_members = ["serviceAccount:app@acme-dev-host-abcd.iam.gserviceaccount.com"]
      value_version    = 4
    }
    saas_secret_bridge_value = "{\"api_url\":\"https://abcd.supabase.co\"}"
  }

  assert {
    condition     = output.components.saas_secret_bridge && length(module.saas_secret_bridge) == 1
    error_message = "Enabling the bridge must instantiate the secret-manager module once."
  }
}

run "vm_operations_can_be_disabled" {
  command = plan

  variables {
    vm_operations = { enable_backup_policy = false, enable_os_patch_management = false }
  }

  assert {
    condition     = length(module.vm_backup_policy) == 0 && length(module.os_patch_management) == 0 && length(google_project_service.osconfig) == 0
    error_message = "Disabled VM operations must create no snapshot policy, patch deployment or osconfig enablement."
  }
}

run "no_additional_regions_unchanged" {
  command = plan

  assert {
    condition     = module.host.additional_region_subnets == {} && module.host.additional_region_routers == {}
    error_message = "network.additional_regions = {} (default) must keep the spoke single-region."
  }
}

run "spoke_additional_region_router_nat" {
  command = plan

  variables {
    network = {
      additional_regions = {
        "europe-west4" = {
          subnet_cidrs = { public = "10.11.0.0/24", private = "10.11.16.0/24", database = "10.11.32.0/24" }
        }
      }
    }
  }

  assert {
    condition     = keys(module.host.additional_region_subnets) == ["europe-west4"] && module.host.additional_region_subnets["europe-west4"].private.subnet.name == "acme-dev-vpc-private-europe-west4"
    error_message = "network.additional_regions must reach net-spoke and plan the region's subnets."
  }

  assert {
    condition     = module.host.additional_region_routers == { "europe-west4" = "acme-dev-vpc-router-europe-west4" }
    error_message = "An additional spoke region with nat = true must get its own Cloud Router and NAT."
  }
}
