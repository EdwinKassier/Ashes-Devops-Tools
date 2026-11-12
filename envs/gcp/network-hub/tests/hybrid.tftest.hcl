# Hybrid connectivity (gcp.network.vpn / gcp.network.interconnect) and extra hub regions (gcp.network.additional_regions) reach the
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

# Additional hub regions (gcp.network.additional_regions) take the same path:
# config text -> local.hub_additional_regions -> the stage.
run "no_hub_additional_regions_by_default" {
  command = plan

  variables {
    landing_zone_config_path = ""
  }

  assert {
    condition     = length(local.hub_additional_regions) == 0
    error_message = "With no config and no variable, the hub must stay single-region (empty hub_additional_regions)."
  }
}

run "hub_additional_regions_from_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-regions.yaml"
  }

  assert {
    condition     = keys(local.hub_additional_regions) == ["europe-west4"] && local.hub_additional_regions["europe-west4"].subnet_cidrs.private == "10.2.16.0/24" && local.hub_additional_regions["europe-west4"].nat == false
    error_message = "gcp.network.additional_regions must reach the stage from the config file."
  }
}

run "hub_additional_regions_variable_wins" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-regions.yaml"
    hub_additional_regions   = {}
  }

  assert {
    condition     = length(local.hub_additional_regions) == 0
    error_message = "An explicit hub_additional_regions variable must win over the config file."
  }
}

# Production is the is_production flag alone: a config environment without it
# fails the plan, naming the entry, instead of silently counting as non-prod.
run "config_environment_without_is_production_fails" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-missing-is-production.yaml"
    environments             = null
  }

  expect_failures = [var.environments]
}

# Routes announced on-premises and hybrid DNS (ARC-12): the root derives the
# environment CIDRs from the environments map and reads gcp.network.hybrid_dns.
run "environment_ranges_and_hybrid_dns_reach_the_stage" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-hybrid.yaml"
  }

  assert {
    condition     = jsonencode(local.hybrid_advertised_ranges) == jsonencode([{ description = "environment dev", range = "10.10.0.0/16" }])
    error_message = "Every environment CIDR must reach the stage as a hybrid advertised range."
  }

  assert {
    condition     = local.hybrid_dns.enable_inbound_forwarding == true && local.hybrid_dns.forward_zones.corp.dns_name == "corp.example.com." && length(local.hybrid_dns.forward_zones.corp.target_ips) == 2
    error_message = "gcp.network.hybrid_dns must reach the stage from the config file."
  }
}

run "no_hybrid_dns_config_is_empty" {
  command = plan

  variables {
    landing_zone_config_path = ""
  }

  assert {
    condition     = length(local.hybrid_dns) == 0
    error_message = "Without config or variable, hybrid_dns is {} (the stage defaults: inbound forwarding only, used only with VPN or Interconnect)."
  }
}

run "hybrid_dns_variable_wins" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-hybrid.yaml"
    hybrid_dns               = { enable_inbound_forwarding = false }
  }

  assert {
    condition     = local.hybrid_dns.enable_inbound_forwarding == false && length(local.hybrid_dns.forward_zones) == 0
    error_message = "An explicit hybrid_dns variable must win over the config file."
  }
}

# The vpn, interconnects and hub_additional_regions inputs are untyped (so a
# misspelled key stays visible), and a validation rejects every key outside
# allowed_keys.tf: the stage's object types would drop it silently. The
# variable runs use nested typos; config_unknown_keys_fail uses top-level ones.
run "vpn_unknown_key_fails" {
  command = plan

  variables {
    landing_zone_config_path = ""
    vpn                      = { enabled = true, tunnel_count = 2, advertised_ip_ranges = [{ range = "10.0.0.0/16", desc = "hub" }] }
  }

  expect_failures = [var.vpn]
}

run "interconnects_unknown_key_fails" {
  command = plan

  variables {
    landing_zone_config_path = ""
    interconnects            = { "hub-partner-1" = { region = "europe-west1", router_name = "hub-ic-router", advertised_ip_ranges = [{ range = "10.0.0.0/16", descripton = "hub" }] } }
  }

  expect_failures = [var.interconnects]
}

run "hub_additional_regions_unknown_key_fails" {
  command = plan

  variables {
    landing_zone_config_path = ""
    hub_additional_regions = {
      "europe-west4" = {
        subnet_cidrs     = { public = "10.2.0.0/24", privat = "10.2.16.0/24", database = "10.2.32.0/24" }
        secondary_ranges = [{ range_name = "pods", ip_cidr_rang = "10.3.0.0/20" }]
      }
    }
  }

  expect_failures = [var.hub_additional_regions]
}

# The same check covers the config file (gcp.network.vpn, interconnect and
# additional_regions), not only the variables.
run "config_unknown_keys_fail" {
  command = plan

  variables {
    landing_zone_config_path = "../../../config/tests/gcp_network_unknown_keys.yaml"
  }

  expect_failures = [var.vpn, var.interconnects, var.hub_additional_regions]
}

run "known_keys_pass" {
  command = plan

  variables {
    landing_zone_config_path = ""
    vpn                      = { enabled = false, tunnel_count = 2, advertised_ip_ranges = [{ range = "10.0.0.0/16", description = "hub" }] }
    interconnects            = { "hub-partner-1" = { region = "europe-west1", router_name = "hub-ic-router", vlan_tag = 100 } }
    hub_additional_regions = {
      "europe-west4" = {
        subnet_cidrs     = { public = "10.2.0.0/24", private = "10.2.16.0/24", database = "10.2.32.0/24" }
        secondary_ranges = [{ range_name = "pods", ip_cidr_range = "10.3.0.0/20" }]
        nat              = false
      }
    }
  }

  assert {
    condition     = local.interconnects["hub-partner-1"].vlan_tag == 100 && local.hub_additional_regions["europe-west4"].nat == false
    error_message = "Inputs that use only the stage's keys must plan."
  }
}
