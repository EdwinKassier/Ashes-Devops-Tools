# Stage contract overrides (FAST-style): a supplied <layer>_contract (variable or
# gcp.contracts.<layer> in config/landing-zone.yaml) replaces the upstream
# terraform_remote_state read entirely. NO remote-state override_data here —
# every run proves the root plans without the upstream workspaces
# (length(data...) == 0). The spoke network is overridden: its own tests cover it.

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
  target = module.environment.module.host
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
      output.host_project_id == "acme-dev-host-abcd" &&
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
        contract = {
          hub_network = {
            vpc_self_link = "https://www.googleapis.com/compute/v1/projects/remote-hub/global/networks/hub-vpc"
            dns_domain    = "remote.internal."
          }
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
      output.host_project_id == "cfgco-dev-host" &&
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

# Hub connectivity: peering by default; ncc joins the NCC hub named by the
# gcp-network-hub contract (DNS peering zone kept, hub VPC peering dropped by
# stages/net-spoke).
run "connectivity_defaults_to_peering" {
  command = plan

  variables {
    network_hub_contract = {
      vpc_self_link = "https://www.googleapis.com/compute/v1/projects/acme-hub/global/networks/hub-vpc"
      dns_domain    = "hub.internal."
    }
  }

  assert {
    condition     = local.network_connectivity == "peering" && local.hub_ncc.hub_id == null && local.hub_ncc.group == "edge"
    error_message = "With no connectivity setting the environment must keep VPC peering."
  }
}

run "connectivity_ncc_from_contract" {
  command = plan

  variables {
    network_connectivity = "ncc"
    network_hub_contract = {
      vpc_self_link   = "https://www.googleapis.com/compute/v1/projects/acme-hub/global/networks/hub-vpc"
      dns_domain      = "hub.internal."
      ncc_hub_id      = "projects/acme-hub/locations/global/hubs/acme-ncc-hub"
      ncc_spoke_group = "default"
    }
  }

  assert {
    condition     = local.network_connectivity == "ncc" && local.hub_ncc.hub_id == "projects/acme-hub/locations/global/hubs/acme-ncc-hub" && local.hub_ncc.group == "default"
    error_message = "network_connectivity = ncc must pass the contract's NCC hub ID and spoke group to the host network."
  }

  assert {
    condition     = local.hub_dns_zones["internal-peering"].dns_name == "hub.internal."
    error_message = "The hub DNS peering zone must stay in ncc mode (DNS peering is not VPC peering)."
  }
}

run "connectivity_ncc_from_remote_state" {
  command = plan

  variables {
    network_connectivity = "ncc"
  }

  override_data {
    target = data.terraform_remote_state.network_hub
    values = {
      outputs = {
        contract = {
          hub_network = {
            vpc_self_link   = "https://www.googleapis.com/compute/v1/projects/remote-hub/global/networks/hub-vpc"
            dns_domain      = "remote.internal."
            ncc_hub_id      = "projects/remote-hub/locations/global/hubs/remote-ncc-hub"
            ncc_spoke_group = "edge"
          }
        }
      }
    }
  }

  assert {
    condition     = local.hub_ncc.hub_id == "projects/remote-hub/locations/global/hubs/remote-ncc-hub" && local.hub_ncc.group == "edge"
    error_message = "The NCC hub ID must come from the gcp-network-hub remote-state contract."
  }
}

# A producer state from before the NCC keys existed still plans (peering).
run "pre_ncc_hub_contract_keeps_peering" {
  command = plan

  override_data {
    target = data.terraform_remote_state.network_hub
    values = {
      outputs = {
        contract = {
          hub_network = {
            vpc_self_link = "https://www.googleapis.com/compute/v1/projects/remote-hub/global/networks/hub-vpc"
            dns_domain    = "remote.internal."
          }
        }
      }
    }
  }

  assert {
    condition     = local.network_connectivity == "peering" && local.hub_ncc.hub_id == null
    error_message = "A gcp-network-hub contract without the NCC keys must still plan, in peering mode."
  }
}

# gcp.environments.<env>.network_connectivity overrides gcp.network.connectivity.
run "connectivity_per_environment_from_config_file" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-ncc.yaml"
    project_prefix           = null
    tfc_organization         = null
    organization_contract    = null
    projects_contract        = null
  }

  assert {
    condition     = local.network_connectivity == "ncc" && local.hub_ncc.hub_id == "projects/cfgco-hub/locations/global/hubs/cfgco-ncc-hub"
    error_message = "gcp.environments.dev.network_connectivity = ncc must win over gcp.network.connectivity, with the hub ID from gcp.contracts.network_hub."
  }
}

# gcp.environments.<env>.additional_regions reaches the environment stage.
run "additional_regions_per_environment_from_config_file" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-regions.yaml"
    project_prefix           = null
    tfc_organization         = null
    organization_contract    = null
    projects_contract        = null
  }

  assert {
    condition     = keys(local.additional_regions) == ["europe-west4"] && local.additional_regions["europe-west4"].subnet_cidrs.private == "10.11.16.0/24"
    error_message = "gcp.environments.dev.additional_regions must reach the environment stage from the config file."
  }
}

run "no_additional_regions_by_default" {
  command = plan

  # Same contracts, no additional_regions entry.
  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-ncc.yaml"
    project_prefix           = null
    tfc_organization         = null
    organization_contract    = null
    projects_contract        = null
  }

  assert {
    condition     = length(local.additional_regions) == 0
    error_message = "With no config entry and no variable the spoke must stay single-region."
  }
}

run "standalone_forces_peering" {
  command = plan

  variables {
    enable_network_hub   = false
    network_connectivity = "ncc"
  }

  assert {
    condition     = local.network_connectivity == "peering" && length(local.hub_vpc_peerings) == 0
    error_message = "Without the network hub there is nothing to join: connectivity stays peering with no peerings."
  }
}

run "rejects_unknown_network_connectivity" {
  command = plan

  variables {
    network_connectivity = "transit"
    network_hub_contract = {
      vpc_self_link = "https://www.googleapis.com/compute/v1/projects/acme-hub/global/networks/hub-vpc"
      dns_domain    = "hub.internal."
    }
  }

  expect_failures = [var.network_connectivity]
}
