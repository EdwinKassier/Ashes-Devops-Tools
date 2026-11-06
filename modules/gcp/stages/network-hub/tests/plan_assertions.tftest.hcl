# Plan assertions for the network-hub stage.
#
# The stage composes net-hub (module.hub), dns-anchor (module.dns_anchor) and a
# standalone Cloud Armor policy. module.hub is overridden (its zone discovery
# and deep primitive tree are covered by net-hub's own suites). dns-anchor is
# planned for real down to its DNS zone, with only its network core
# (module.dns_anchor.module.network) and zone data source stubbed, so the
# private-zone binding to the anchor VPC is proven on the planned
# google_dns_managed_zone resource.

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
    shared = {
      id           = "folders/111111111"
      name         = "folders/111111111"
      display_name = "Shared"
    }
  }
}

override_module {
  target = module.hub
  outputs = {
    network_self_link = "projects/mock-hub-project/global/networks/hub-vpc-core"
    network_name      = "hub-vpc-core"
    subnets           = { public = {}, private = { "us-central1-a" = { self_link = "projects/mock-hub-project/regions/us-central1/subnetworks/hub-vpc-core-private-us-central1-a" } }, database = {} }
    nat_ip            = ["203.0.113.10"]
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

run "dns_zone_binds_to_dns_anchor_network_self_link" {
  command = plan

  assert {
    condition     = keys(module.dns_anchor.dns_zones) == ["internal-root"]
    error_message = "The stage must plan exactly the internal-root zone in the DNS anchor (state-compatible key for the moved dns_hub_zone)."
  }

  assert {
    condition = length(module.dns_anchor.dns_zones["internal-root"].zone.private_visibility_config[0].networks) == 1 && alltrue([
      for n in module.dns_anchor.dns_zones["internal-root"].zone.private_visibility_config[0].networks :
      n.network_url == "projects/mock-dns-project/global/networks/dns-vpc-core"
    ])
    error_message = "The private DNS zone must bind to the DNS anchor's own VPC self_link, not the shared-vpc hub network."
  }

  assert {
    condition     = module.dns_anchor.dns_zones["internal-root"].zone.dns_name == "internal.example.com." && module.dns_anchor.dns_zones["internal-root"].zone.description == "Root Internal Zone for Organization"
    error_message = "The root zone must keep its dns_name and description from the stages/host era (no in-place drift after the move)."
  }

  assert {
    condition     = length(module.dns_anchor.dns_zones["internal-root"].zone.cloud_logging_config) == 1 && module.dns_anchor.dns_zones["internal-root"].zone.cloud_logging_config[0].enable_logging
    error_message = "The root zone must keep DNS query logging on."
  }
}

# The stage outputs keep their names and sources across the decomposition, so
# gcp-network-hub consumers (and gcp-workload via remote state) are unaffected.
run "stage_outputs_unchanged_after_decomposition" {
  command = plan

  assert {
    condition     = output.hub_vpc_self_link == "projects/mock-hub-project/global/networks/hub-vpc-core" && output.hub_vpc_name == "hub-vpc-core"
    error_message = "hub_vpc_self_link / hub_vpc_name must come from module.hub."
  }

  assert {
    condition     = output.hub_subnet_self_links == { "us-central1-a" = "projects/mock-hub-project/regions/us-central1/subnetworks/hub-vpc-core-private-us-central1-a" }
    error_message = "hub_subnet_self_links must map the hub private subnets by zone."
  }

  assert {
    condition     = output.hub_nat_ips == ["203.0.113.10"]
    error_message = "hub_nat_ips must come from module.hub.nat_ip."
  }

  assert {
    condition     = output.hub_dns_domain == "internal.example.com." && output.dns_zone_name == "internal-root"
    error_message = "hub_dns_domain / dns_zone_name must come from the dns-anchor internal-root zone."
  }
}

# The hub Cloud Armor policy stages/host created by default is preserved as a
# standalone primitive with identical settings (moved, not recreated).
run "hub_cloud_armor_preserved" {
  command = plan

  assert {
    condition     = module.hub_cloud_armor.policy_name == "mock-security-policy"
    error_message = "The hub Cloud Armor policy must keep the <project_prefix>-security-policy name."
  }
}

# Audit M (network gaps): the SSH/RDP deny must be associated with every folder,
# not just the shared folder.
run "ssh_rdp_deny_associated_with_every_folder" {
  command = plan

  variables {
    folders = {
      shared = { id = "folders/111111111", name = "folders/111111111", display_name = "Shared" }
      dev    = { id = "folders/222222222", name = "folders/222222222", display_name = "Development" }
      prod   = { id = "folders/333333333", name = "folders/333333333", display_name = "Production" }
    }
  }

  assert {
    condition     = toset(output.hierarchical_firewall_association_targets) == toset(["folders/111111111", "folders/222222222", "folders/333333333"])
    error_message = "the hub SSH/RDP deny policy must be associated with the shared folder AND every environment folder."
  }
}
