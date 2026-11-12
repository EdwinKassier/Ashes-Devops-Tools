# Hybrid connectivity (HA VPN, Cloud Interconnect) reaches net-hub through the
# network-hub stage. module.hub is NOT overridden here: only its zone lookup
# and the tiered VPC core are stubbed, so the vpn / ncc-spoke / interconnect
# instances are planned for real. The pre-shared key is write-only.

mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  project_prefix         = "mock"
  hub_vpc_cidr_block     = "10.0.0.0/16"
  dns_hub_vpc_cidr_block = "10.1.0.0/16"
  default_region         = "us-central1"
  hub_project_id         = "mock-hub-project"
  dns_project_id         = "mock-dns-project"
  spoke_project_numbers  = {}
  org_id                 = "organizations/123456789"
  internal_domain        = "internal.example.com"
  folders = {
    shared = { id = "folders/111111111", name = "folders/111111111", display_name = "Shared" }
  }
}

override_data {
  target = module.hub.data.google_compute_zones.available
  values = {
    names = ["us-central1-a"]
  }
}

override_module {
  target = module.hub.module.network
  outputs = {
    network_self_link = "projects/mock-hub-project/global/networks/hub-vpc-core"
    network_id        = "projects/mock-hub-project/global/networks/hub-vpc-core"
    network_name      = "hub-vpc-core"
    subnets           = { public = {}, private = {}, database = {} }
  }
}

override_data {
  target = module.dns_anchor.data.google_compute_zones.available
  values = {
    names = ["us-central1-a"]
  }
}

override_module {
  target = module.dns_anchor.module.network
  outputs = {
    network_self_link = "projects/mock-dns-project/global/networks/dns-vpc-core"
    network_id        = "projects/mock-dns-project/global/networks/dns-vpc-core"
    network_name      = "dns-vpc-core"
    subnets           = { public = {}, private = {}, database = {} }
  }
}

run "vpn_off_by_default" {
  command = plan

  assert {
    condition     = !output.hybrid_connectivity.vpn && !output.hybrid_connectivity.ncc_vpn_spoke && length(output.hybrid_connectivity.interconnects) == 0
    error_message = "VPN, Interconnect and the NCC hybrid spoke must be off by default."
  }
}

run "vpn_reaches_net_hub_with_write_only_key" {
  command = plan

  variables {
    vpn = {
      enabled          = true
      peer_gateway_ips = ["203.0.113.1", "203.0.113.2"]
    }
    vpn_shared_secret_wo         = "mock-psk-not-a-secret"
    vpn_shared_secret_wo_version = 3
    interconnects = {
      "ic-partner-1" = { region = "us-central1", router_name = "hub-ic-router" }
    }
  }

  assert {
    condition     = output.hybrid_connectivity.vpn && join(",", output.hybrid_connectivity.interconnects) == "ic-partner-1"
    error_message = "vpn / interconnects set on the stage must plan the net-hub VPN and Interconnect."
  }

  assert {
    condition     = !output.hybrid_connectivity.ncc_vpn_spoke
    error_message = "Without the NCC hub there is no hybrid spoke."
  }
}

run "vpn_becomes_ncc_hybrid_spoke" {
  command = plan

  variables {
    enable_ncc_hub = true
    vpn = {
      enabled                    = true
      peer_gateway_ips           = ["203.0.113.1", "203.0.113.2"]
      site_to_site_data_transfer = true
    }
    vpn_shared_secret_wo = "mock-psk-not-a-secret"
  }

  assert {
    condition     = output.hybrid_connectivity.ncc_vpn_spoke
    error_message = "With NCC and VPN both enabled the tunnels must join the hub as a hybrid spoke."
  }
}

# Additional hub regions are also planned through the real module.hub (only
# its tiered VPC core is stubbed), so the per-region router and NAT show up.
run "no_hub_additional_regions_unchanged" {
  command = plan

  assert {
    condition     = module.hub.additional_region_routers == {}
    error_message = "hub_additional_regions = {} (default) must plan no additional-region router or NAT."
  }
}

run "hub_additional_region_router_nat" {
  command = plan

  variables {
    hub_additional_regions = {
      "us-east4" = {
        subnet_cidrs = { public = "10.2.0.0/24", private = "10.2.16.0/24", database = "10.2.32.0/24" }
      }
    }
  }

  override_module {
    target = module.hub.module.network
    outputs = {
      network_self_link = "projects/mock-hub-project/global/networks/hub-vpc-core"
      network_id        = "projects/mock-hub-project/global/networks/hub-vpc-core"
      network_name      = "hub-vpc-core"
      subnets           = { public = {}, private = {}, database = {} }
      additional_region_subnets = {
        "us-east4" = {
          public   = { self_link = "projects/mock-hub-project/regions/us-east4/subnetworks/hub-vpc-core-public-us-east4" }
          private  = { self_link = "projects/mock-hub-project/regions/us-east4/subnetworks/hub-vpc-core-private-us-east4" }
          database = { self_link = "projects/mock-hub-project/regions/us-east4/subnetworks/hub-vpc-core-db-us-east4" }
        }
      }
    }
  }

  assert {
    condition     = module.hub.additional_region_routers == { "us-east4" = "hub-vpc-core-router-us-east4" }
    error_message = "hub_additional_regions must reach net-hub and plan a router and NAT in the extra region."
  }
}

# ── Routes announced on-premises and hybrid DNS (ARC-12) ─────────────────────
# DEFAULT BGP mode announces the hub VPC's own subnets only, never the peered
# environment ranges. With no explicit advertised_ip_ranges the router moves to
# CUSTOM mode with the ALL_SUBNETS group (every hub subnet, what DEFAULT
# announced) plus each environment CIDR, so the announcement is a superset.

run "vpn_advertises_hub_and_environment_ranges_by_default" {
  command = plan

  variables {
    vpn = {
      enabled          = true
      peer_gateway_ips = ["203.0.113.1", "203.0.113.2"]
    }
    vpn_shared_secret_wo     = "mock-psk-not-a-secret"
    hybrid_advertised_ranges = [{ range = "10.10.0.0/16", description = "environment dev" }]
  }

  assert {
    condition     = jsonencode(local.vpn_effective.advertised_groups) == jsonencode(["ALL_SUBNETS"])
    error_message = "The derived announcement must keep every hub subnet (ALL_SUBNETS), so on-premises loses no route DEFAULT mode announced."
  }

  assert {
    condition     = jsonencode(local.vpn_effective.advertised_ip_ranges) == jsonencode([{ description = "environment dev", range = "10.10.0.0/16" }])
    error_message = "DEFAULT BGP mode never announces peered spokes: every environment CIDR must be advertised (ARC-12)."
  }

  assert {
    condition     = length(google_dns_policy.hub_inbound) == 1 && google_dns_policy.hub_inbound[0].enable_inbound_forwarding && one(google_dns_policy.hub_inbound[0].networks).network_url == "projects/mock-hub-project/global/networks/hub-vpc-core"
    error_message = "On-premises resolvers need an inbound forwarding address in the hub VPC (the VPC the VPN lands in)."
  }

  assert {
    condition     = length(module.hybrid_forward_zones) == 0
    error_message = "No forward zone is created unless hybrid_dns.forward_zones lists one."
  }
}

run "explicit_advertised_ranges_win" {
  command = plan

  variables {
    vpn = {
      enabled              = true
      peer_gateway_ips     = ["203.0.113.1", "203.0.113.2"]
      advertised_ip_ranges = [{ range = "10.0.0.0/12", description = "GCP block" }]
    }
    vpn_shared_secret_wo     = "mock-psk-not-a-secret"
    hybrid_advertised_ranges = [{ range = "10.10.0.0/16", description = "environment dev" }]
  }

  assert {
    condition     = jsonencode(local.vpn_effective.advertised_ip_ranges) == jsonencode([{ description = "GCP block", range = "10.0.0.0/12" }]) && length(local.vpn_effective.advertised_groups) == 0
    error_message = "Explicit vpn.advertised_ip_ranges must win over the derived list, with the groups the caller set (none)."
  }
}

run "interconnect_advertises_environment_ranges_by_default" {
  command = plan

  variables {
    interconnects = {
      "ic-partner-1" = { region = "us-central1", router_name = "hub-ic-router" }
      "ic-partner-2" = {
        region               = "us-central1"
        router_name          = "hub-ic-router-2"
        advertised_ip_ranges = [{ range = "10.0.0.0/12", description = "GCP block" }]
      }
    }
    hybrid_advertised_ranges = [{ range = "10.10.0.0/16", description = "environment dev" }]
  }

  assert {
    condition     = jsonencode(local.interconnects_effective["ic-partner-1"].advertised_ip_ranges) == jsonencode([{ description = "environment dev", range = "10.10.0.0/16" }])
    error_message = "An Interconnect without advertised_ip_ranges must announce the environment CIDRs (its router keeps ALL_SUBNETS in CUSTOM mode)."
  }

  assert {
    condition     = jsonencode(local.interconnects_effective["ic-partner-2"].advertised_ip_ranges) == jsonencode([{ description = "GCP block", range = "10.0.0.0/12" }])
    error_message = "An Interconnect's explicit advertised_ip_ranges must win."
  }

  assert {
    condition     = length(google_dns_policy.hub_inbound) == 1
    error_message = "An Interconnect alone also turns on the inbound DNS policy."
  }
}

run "on_prem_zones_are_forwarded" {
  command = plan

  variables {
    vpn = {
      enabled          = true
      peer_gateway_ips = ["203.0.113.1", "203.0.113.2"]
    }
    vpn_shared_secret_wo = "mock-psk-not-a-secret"
    hybrid_dns = {
      forward_zones = { corp = { dns_name = "corp.example.com.", target_ips = ["192.168.0.10", "192.168.0.11"] } }
    }
  }

  assert {
    condition = (
      module.hybrid_forward_zones["corp"].zone.dns_name == "corp.example.com." &&
      length(module.hybrid_forward_zones["corp"].zone.forwarding_config[0].target_name_servers) == 2 &&
      alltrue([for t in module.hybrid_forward_zones["corp"].zone.forwarding_config[0].target_name_servers : t.forwarding_path == "private"]) &&
      one(module.hybrid_forward_zones["corp"].zone.private_visibility_config[0].networks).network_url == "projects/mock-hub-project/global/networks/hub-vpc-core"
    )
    error_message = "On-premises domains must be forwarded from the hub VPC to the on-premises resolvers over the private path."
  }

  # Cloud DNS sends forwarded queries from 35.199.192.0/19; with dynamic
  # routing the on-premises side learns the return route from the router.
  assert {
    condition     = contains([for r in local.vpn_effective.advertised_ip_ranges : r.range], "35.199.192.0/19")
    error_message = "Forward zones need 35.199.192.0/19 announced so on-premises resolvers can answer."
  }
}

run "no_hybrid_no_dns_policy" {
  command = plan

  variables {
    hybrid_dns = {
      forward_zones = { corp = { dns_name = "corp.example.com.", target_ips = ["192.168.0.10"] } }
    }
  }

  assert {
    condition     = length(google_dns_policy.hub_inbound) == 0 && length(module.hybrid_forward_zones) == 0
    error_message = "Without VPN or Interconnect nothing hybrid is created."
  }
}

run "inbound_forwarding_can_be_turned_off" {
  command = plan

  variables {
    vpn = {
      enabled          = true
      peer_gateway_ips = ["203.0.113.1", "203.0.113.2"]
    }
    vpn_shared_secret_wo = "mock-psk-not-a-secret"
    hybrid_dns           = { enable_inbound_forwarding = false }
  }

  assert {
    condition     = length(google_dns_policy.hub_inbound) == 0
    error_message = "enable_inbound_forwarding = false must skip the inbound DNS policy."
  }
}

# The internal zone (internal_domain) is bound to the hub VPC. Two private
# zones bound to one network cannot share an origin, and a forwarded subdomain
# would hide part of the internal zone from the hub.
run "rejects_forwarding_the_internal_domain" {
  command = plan

  variables {
    hybrid_dns = {
      forward_zones = { internal = { dns_name = "internal.example.com.", target_ips = ["192.168.0.10"] } }
    }
  }

  expect_failures = [var.hybrid_dns]
}

run "rejects_forwarding_a_subdomain_of_the_internal_domain" {
  command = plan

  variables {
    hybrid_dns = {
      forward_zones = { sub = { dns_name = "corp.internal.example.com.", target_ips = ["192.168.0.10"] } }
    }
  }

  expect_failures = [var.hybrid_dns]
}

run "rejects_forward_zone_without_trailing_dot" {
  command = plan

  variables {
    hybrid_dns = {
      forward_zones = { corp = { dns_name = "corp.example.com", target_ips = ["192.168.0.10"] } }
    }
  }

  expect_failures = [var.hybrid_dns]
}
