# Plan assertions for the host stage: verify the composed VPC identity is wired through
# to the stage outputs when networking is enabled.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {
  mock_data "google_compute_zones" {
    defaults = {
      names = ["europe-west1-b", "europe-west1-c", "europe-west1-d"]
    }
  }
}
mock_provider "google-beta" {}

variables {
  project_id        = "mock-project"
  project_prefix    = "mock"
  vpc_cidr_block    = "10.0.0.0/16"
  vpc_name          = "mock-vpc"
  enable_networking = true
}

run "network_outputs_wired_from_vpc_module" {
  command = plan

  assert {
    condition     = output.network_name == var.vpc_name
    error_message = "Stage network_name output must come from the composed VPC module."
  }

  assert {
    condition     = length(output.network_tags) >= 1
    error_message = "Stage must expose the tiered network tags."
  }
}

run "networking_disabled_falls_back_to_existing_network" {
  command = plan

  variables {
    enable_networking     = false
    existing_network_name = "shared-host-vpc"
  }

  assert {
    condition     = output.network_name == "shared-host-vpc"
    error_message = "With networking disabled, network_name must fall back to existing_network_name."
  }
}

# --- Behavioural plan assertions: subnets, NAT, firewall, PSA, edge, DNS ------
# explicit_zones pins the zone set so per-zone for_each keys and derived CIDRs
# are deterministic (the data source is mocked in the default runs above).

run "three_tier_subnets_derived_and_hardened" {
  command = plan

  variables {
    region         = "europe-west1"
    explicit_zones = ["europe-west1-b", "europe-west1-c"]
  }

  assert {
    condition     = toset(keys(module.private_subnets)) == toset(["europe-west1-b", "europe-west1-c"]) && toset(keys(module.public_subnets)) == toset(keys(module.database_subnets))
    error_message = "One subnet per tier must be planned per zone, keyed by zone name."
  }

  assert {
    condition     = module.public_subnets["europe-west1-b"].subnet.name == "mock-vpc-public-europe-west1-b" && module.private_subnets["europe-west1-c"].subnet.name == "mock-vpc-private-europe-west1-c" && module.database_subnets["europe-west1-b"].subnet.name == "mock-vpc-db-europe-west1-b"
    error_message = "Subnet names must be derived as <vpc_name>-<tier>-<zone>."
  }

  assert {
    condition     = [for z in ["europe-west1-b", "europe-west1-c"] : module.public_subnets[z].subnet.ip_cidr_range] == ["10.0.0.0/24", "10.0.1.0/24"] && [for z in ["europe-west1-b", "europe-west1-c"] : module.private_subnets[z].subnet.ip_cidr_range] == ["10.0.16.0/24", "10.0.17.0/24"] && [for z in ["europe-west1-b", "europe-west1-c"] : module.database_subnets[z].subnet.ip_cidr_range] == ["10.0.32.0/24", "10.0.33.0/24"]
    error_message = "Auto CIDRs must be cidrsubnet(vpc_cidr, 8, i / 16+i / 32+i) for public / private / database tiers."
  }

  assert {
    condition = alltrue(concat(
      [for s in module.private_subnets : s.subnet.private_ip_google_access],
      [for s in module.database_subnets : s.subnet.private_ip_google_access],
    ))
    error_message = "Private and database subnets must have Private Google Access enabled."
  }

  assert {
    condition = alltrue([
      for s in concat(values(module.public_subnets), values(module.private_subnets), values(module.database_subnets)) :
      length(s.subnet.log_config) == 1 && s.subnet.log_config[0].aggregation_interval == "INTERVAL_5_SEC" && s.subnet.log_config[0].flow_sampling == 0.5
    ])
    error_message = "Every subnet in every tier must have VPC flow logs enabled with the stage defaults."
  }

  assert {
    condition     = length(module.private_subnets["europe-west1-b"].subnet.secondary_ip_range) == 0
    error_message = "No GKE secondary ranges must be rendered unless secondary_ranges is set for the zone."
  }

  assert {
    condition     = length(terraform_data.subnet_cidr_count_guard) == 1 && length(terraform_data.deletion_protection_guard) == 0
    error_message = "CIDR-count guard must be planned with networking; deletion guard must be off by default."
  }
}

run "integrated_nat_scoped_and_logged" {
  command = plan

  variables {
    region         = "europe-west1"
    explicit_zones = ["europe-west1-b", "europe-west1-c"]
  }

  assert {
    condition     = length(module.integrated_nat) == 1
    error_message = "Integrated Cloud NAT must be enabled by default."
  }

  assert {
    condition     = module.integrated_nat[0].name == "mock-vpc-nat" && module.integrated_nat[0].router_name == "mock-vpc-router"
    error_message = "NAT and router names must be derived from vpc_name."
  }

  assert {
    condition     = module.integrated_nat[0].nat.source_subnetwork_ip_ranges_to_nat == "LIST_OF_SUBNETWORKS"
    error_message = "Integrated NAT must be scoped to an explicit subnet list (public tier excluded), not ALL_SUBNETWORKS."
  }

  assert {
    condition     = length(module.integrated_nat[0].nat.log_config) == 1 && module.integrated_nat[0].nat.log_config[0].enable == true && module.integrated_nat[0].nat.log_config[0].filter == "ERRORS_ONLY"
    error_message = "Integrated NAT logging must be enabled with the ERRORS_ONLY filter by default."
  }

  assert {
    condition     = module.integrated_nat[0].nat.nat_ip_allocate_option == "AUTO_ONLY"
    error_message = "Integrated NAT must default to AUTO_ONLY allocation."
  }
}

run "firewall_baseline" {
  command = plan

  variables {
    region         = "europe-west1"
    explicit_zones = ["europe-west1-b"]
  }

  assert {
    condition     = module.firewall_deny_all[0].name == "mock-vpc-deny-all-ingress"
    error_message = "A catch-all deny-all-ingress rule must be planned with a vpc_name-derived name."
  }

  assert {
    condition     = module.firewall_database_deny_egress[0].name == "mock-vpc-deny-db-egress"
    error_message = "A database-tier egress deny rule must be planned (defense in depth)."
  }

  assert {
    condition = toset([
      module.firewall_apigateway_to_public[0].name,
      module.firewall_public_to_compute[0].name,
      module.firewall_compute_to_database[0].name,
      module.firewall_health_checks[0].name,
      module.firewall_iap_ssh_rdp[0].name,
      ]) == toset([
      "mock-vpc-allow-apigw-public",
      "mock-vpc-allow-public-compute",
      "mock-vpc-allow-compute-db",
      "mock-vpc-allow-health-checks",
      "mock-vpc-allow-iap-ssh-rdp",
    ])
    error_message = "Tiered allow rules (apigw->public->compute->db), health checks and IAP must all be planned by default."
  }

  assert {
    condition     = length(module.additional_firewall_rules) == 0 && length(module.hierarchical_firewall_policies) == 0
    error_message = "No additional or hierarchical firewall rules must be planned by default."
  }
}

run "psa_psc_and_edge_defaults" {
  command = plan

  variables {
    region         = "europe-west1"
    explicit_zones = ["europe-west1-b"]
  }

  assert {
    condition     = length(module.private_service_access) == 1 && length(module.private_service_connect) == 1
    error_message = "Private Service Access and Private Service Connect must be enabled by default."
  }

  assert {
    condition     = module.private_service_access[0].address_resource.purpose == "VPC_PEERING" && module.private_service_access[0].address_resource.address_type == "INTERNAL" && module.private_service_access[0].address_resource.prefix_length == 16
    error_message = "PSA must reserve an INTERNAL VPC_PEERING /16 range by default."
  }

  assert {
    condition     = output.private_service_access_range_name == "google-managed-services"
    error_message = "PSA range name output must be the default psa_name."
  }

  assert {
    condition     = module.cloud_armor[0].policy_name == "mock-security-policy"
    error_message = "Cloud Armor policy must be on by default, named <project_prefix>-security-policy."
  }

  assert {
    condition     = length(module.vpn) == 0 && length(module.cdn) == 0 && length(module.api_gateway) == 0 && length(module.vpc_flow_logs) == 0 && length(module.flow_logs_kms) == 0
    error_message = "VPN, CDN, API Gateway and flow-log export must be opt-in (absent by default)."
  }

  assert {
    condition     = length(module.shared_vpc_service_projects) == 0 && length(module.dns) == 0
    error_message = "No Shared VPC attachments or DNS zones must be planned by default."
  }
}

run "toggles_disable_optional_networking" {
  command = plan

  variables {
    region                         = "europe-west1"
    explicit_zones                 = ["europe-west1-b"]
    enable_cloud_nat               = false
    enable_iap_access              = false
    enable_private_service_access  = false
    enable_private_service_connect = false
    enable_cloud_armor             = false
    enable_deletion_protection     = true
  }

  assert {
    condition     = length(module.integrated_nat) == 0
    error_message = "enable_cloud_nat = false must drop the integrated NAT."
  }

  assert {
    condition     = length(module.firewall_iap_ssh_rdp) == 0 && length(module.firewall_deny_all) == 1
    error_message = "Disabling IAP must drop only the IAP rule; the deny-all baseline must remain."
  }

  assert {
    condition     = length(module.private_service_access) == 0 && output.private_service_access_range_name == null && length(module.private_service_connect) == 0
    error_message = "Disabling PSA/PSC must drop both modules and null the PSA range output."
  }

  assert {
    condition     = length(module.cloud_armor) == 0
    error_message = "enable_cloud_armor = false must drop the Cloud Armor policy."
  }

  assert {
    condition     = terraform_data.deletion_protection_guard[0].input == "mock-project/mock-vpc"
    error_message = "Deletion guard must be keyed '<project_id>/<vpc_name>' when enabled."
  }
}

run "networking_disabled_skips_all_vpc_resources" {
  command = plan

  variables {
    enable_networking     = false
    existing_network_name = "shared-host-vpc"
    explicit_zones        = ["europe-west1-b"]
  }

  assert {
    condition     = length(module.vpc) == 0 && length(module.public_subnets) == 0 && length(module.private_subnets) == 0 && length(module.database_subnets) == 0
    error_message = "enable_networking = false must not plan a VPC or any subnets."
  }

  assert {
    condition     = length(module.integrated_nat) == 0 && length(module.firewall_deny_all) == 0 && length(module.private_service_access) == 0
    error_message = "enable_networking = false must also skip NAT, baseline firewall rules and PSA."
  }

  assert {
    condition     = output.subnets == null && output.nat_ip == null
    error_message = "Subnet and NAT outputs must be null when networking is disabled."
  }
}

run "private_dns_zone_bound_to_vpc_with_logging" {
  command = plan

  variables {
    explicit_zones = ["europe-west1-b"]
    labels         = { env = "test" }
    dns_zones = {
      internal = {
        dns_name   = "internal.example.com."
        visibility = "private"
        # peering_network and description deliberately omitted: optional attributes
        # arrive as null and dns.tf must null-coalesce them (regression test).
      }
    }
  }

  assert {
    condition     = keys(module.dns) == ["internal"]
    error_message = "One DNS module instance must be planned per dns_zones entry."
  }

  assert {
    condition     = module.dns["internal"].zone.visibility == "private" && module.dns["internal"].zone.name == "internal"
    error_message = "Private zones must be created with private visibility and the map key as name."
  }

  assert {
    condition     = length(module.dns["internal"].zone.cloud_logging_config) == 1 && module.dns["internal"].zone.cloud_logging_config[0].enable_logging == true
    error_message = "The host stage must force DNS query logging on for every zone."
  }

  assert {
    condition     = length(module.dns["internal"].zone.private_visibility_config[0].networks) == 1
    error_message = "Private zones must be bound to exactly the stage VPC."
  }

  assert {
    condition     = module.dns["internal"].zone.labels == tomap({ env = "test" })
    error_message = "Stage labels must propagate to DNS zones."
  }
}
