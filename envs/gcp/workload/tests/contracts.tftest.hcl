# Stage contract overrides (FAST-style): a supplied <layer>_contract (variable or
# gcp.contracts.<layer> in config/landing-zone.yaml) replaces the upstream
# terraform_remote_state read entirely. NO remote-state override_data here —
# every run proves the root plans without the upstream workspaces
# (length(data...) == 0). The host stage is overridden: its own tests cover it.

mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  landing_zone_config_path = ""
  project_prefix           = "acme"
  environment              = "dev"
  tfc_organization         = "acme-tfc"
  monthly_budget_limit     = 0

  organization_contract = {
    org_id               = "123456789012"
    billing_account      = "billingAccounts/000000-111111-222222"
    admin_project_number = "111111111111"
  }
  projects_contract = {
    environment_config = {
      dev = {
        folder_id           = "folders/111"
        host_project_id     = "acme-dev-host-abcd"
        host_project_number = "222222222222"
        region              = "europe-west1"
        cidr_block          = "10.10.0.0/16"
      }
    }
  }
}

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

run "contracts_replace_remote_state" {
  command = plan

  variables {
    network_hub_contract = {
      vpc_self_link = "https://www.googleapis.com/compute/v1/projects/acme-hub/global/networks/hub-vpc"
      dns_domain    = "hub.internal."
    }
  }

  assert {
    condition = (
      length(data.terraform_remote_state.organization) == 0 &&
      length(data.terraform_remote_state.projects) == 0 &&
      length(data.terraform_remote_state.network_hub) == 0
    )
    error_message = "a supplied contract must skip the matching remote-state read"
  }

  assert {
    condition = (
      data.google_project.host_project.project_id == "acme-dev-host-abcd" &&
      local.org_id == "123456789012" &&
      local.hub_vpc_peerings["hub-peering"].peer_network == "https://www.googleapis.com/compute/v1/projects/acme-hub/global/networks/hub-vpc" &&
      local.hub_dns_zones["internal-peering"].dns_name == "hub.internal."
    )
    error_message = "contract values must flow into the host project lookup and the hub peering / DNS peering inputs"
  }
}

# gcp-workload without gcp-network-hub: no hub peering, no DNS peering zone.
run "standalone_without_network_hub" {
  command = plan

  variables {
    enable_network_hub = false
  }

  assert {
    condition = (
      length(data.terraform_remote_state.network_hub) == 0 &&
      local.hub_network == null &&
      length(local.hub_vpc_peerings) == 0 &&
      length(local.hub_dns_zones) == 0
    )
    error_message = "enable_network_hub = false must not read gcp-network-hub and must pass no hub peering / DNS peering zone"
  }
}

# Without a contract the root still reads the upstream workspace (count = 1).
run "remote_state_read_without_contract" {
  command = plan

  override_data {
    target = data.terraform_remote_state.network_hub
    values = {
      outputs = {
        hub_network = {
          vpc_self_link = "https://www.googleapis.com/compute/v1/projects/remote-hub/global/networks/hub-vpc"
          dns_domain    = "remote.internal."
        }
      }
    }
  }

  assert {
    condition     = length(data.terraform_remote_state.network_hub) == 1 && local.hub_dns_zones["internal-peering"].dns_name == "remote.internal."
    error_message = "with no network_hub contract the hub network must come from the gcp-network-hub remote state"
  }
}

# The same contracts from config/landing-zone.yaml (gcp.contracts.<layer>).
run "contracts_from_config_file" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-contracts.yaml"
    project_prefix           = null
    tfc_organization         = null
    organization_contract    = null
    projects_contract        = null
  }

  assert {
    condition = (
      length(data.terraform_remote_state.organization) == 0 &&
      length(data.terraform_remote_state.projects) == 0 &&
      length(data.terraform_remote_state.network_hub) == 0 &&
      data.google_project.host_project.project_id == "cfgco-dev-host" &&
      local.billing_account == "billingAccounts/000000-111111-222222" &&
      local.hub_network.dns_domain == "hub.internal."
    )
    error_message = "gcp.contracts.<layer> in the config file must replace the remote-state reads"
  }
}

run "rejects_malformed_network_hub_contract" {
  command = plan

  variables {
    network_hub_contract = { vpc_self_link = "x", dns_domain = "hub.internal" }
  }

  expect_failures = [var.network_hub_contract]
}
