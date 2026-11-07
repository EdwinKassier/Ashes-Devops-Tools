# Hybrid connectivity (gcp.network.vpn / gcp.network.interconnect) reaches the
# network-hub stage from the config file, and stays off when absent. The stage
# is overridden: the root's job is to hand it the effective values, which the
# locals expose. The stage's own suites assert what it plans from them.

mock_provider "google" {}
mock_provider "google-beta" {}
mock_provider "random" {}

variables {
  project_prefix         = "acme"
  hub_vpc_cidr_block     = "10.0.0.0/16"
  dns_hub_vpc_cidr_block = "10.1.0.0/16"
  environments = {
    dev = {
      display_name            = "Development"
      region                  = "europe-west1"
      cidr_block              = "10.10.0.0/16"
      budget_monthly_limit    = 100
      iam_group_role_bindings = {}
    }
  }
}

override_data {
  target = data.terraform_remote_state.gcp_organization
  values = {
    outputs = {
      contract = {
        org_id  = "123456789012"
        folders = { dev = { id = "folders/111", display_name = "Development" } }
      }
    }
  }
}

override_data {
  target = data.terraform_remote_state.gcp_projects
  values = {
    outputs = {
      contract = {
        project_ids     = { "shared-hub" = "acme-hub-abcd", "shared-dns" = "acme-dns-abcd", "dev-host" = "acme-dev-host-abcd" }
        project_numbers = { "shared-hub" = "111111111111", "shared-dns" = "222222222222", "dev-host" = "333333333333" }
      }
    }
  }
}

override_module {
  target = module.network_hub
  outputs = {
    hub_vpc_self_link = "https://www.googleapis.com/compute/v1/projects/acme-hub-abcd/global/networks/acme-hub-vpc"
    hub_vpc_name      = "acme-hub-vpc"
    dns_zone_name     = "hub-dns"
    hub_dns_domain    = "hub.internal."
  }
}

run "vpn_off_by_default" {
  command = plan

  variables {
    landing_zone_config_path = ""
  }

  assert {
    condition     = length(local.vpn) == 0 && length(local.interconnects) == 0
    error_message = "With no config and no variables, hybrid connectivity must be off: an empty vpn and no interconnects reach the stage."
  }
}

run "gcp_vpn_reaches_net_hub_from_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-hybrid.yaml"
  }

  assert {
    condition     = local.vpn.enabled == true && local.vpn.tunnel_count == 2 && length(local.vpn.peer_gateway_ips) == 2 && local.vpn.advertised_ip_ranges[0].range == "10.0.0.0/16"
    error_message = "gcp.network.vpn must reach the network-hub stage as the effective vpn."
  }

  assert {
    condition     = local.enable_ncc_hub == true && keys(local.interconnects) == ["hub-partner-1"] && local.interconnects["hub-partner-1"].router_name == "hub-ic-router"
    error_message = "gcp.network.interconnect must reach the stage keyed by attachment name, alongside the NCC hub the VPN joins as a hybrid spoke."
  }
}

run "explicit_variable_beats_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-hybrid.yaml"
    vpn                      = { enabled = false }
    interconnects            = {}
  }

  assert {
    condition     = local.vpn.enabled == false && length(local.interconnects) == 0
    error_message = "An explicit vpn / interconnects variable must replace the config value."
  }
}
