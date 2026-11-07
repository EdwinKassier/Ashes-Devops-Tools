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
