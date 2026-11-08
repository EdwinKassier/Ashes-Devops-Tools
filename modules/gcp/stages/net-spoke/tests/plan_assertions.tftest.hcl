# Plan assertions for stages/net-spoke (mock providers, no credentials).

mock_provider "google" {
  mock_data "google_compute_zones" {
    defaults = {
      names = ["europe-west1-b", "europe-west1-c", "europe-west1-d"]
    }
  }
  mock_data "google_project" {
    defaults = {
      number = "123456789012"
    }
  }
}
mock_provider "google-beta" {}

variables {
  project_id     = "mock-host-project"
  project_prefix = "mock-dev"
  region         = "europe-west1"
  network = {
    name           = "mock-dev-vpc"
    cidr_block     = "10.10.0.0/16"
    explicit_zones = ["europe-west1-b", "europe-west1-c"]
  }
}

run "defaults_build_a_secure_spoke" {
  command = plan

  assert {
    condition     = output.network_name == "mock-dev-vpc" && toset(keys(output.subnets.private)) == toset(["europe-west1-b", "europe-west1-c"])
    error_message = "The spoke must plan the named VPC with one private subnet per explicit zone."
  }

  assert {
    condition     = length(module.integrated_nat) == 1 && module.integrated_nat[0].name == "mock-dev-vpc-nat" && module.integrated_nat[0].nat.source_subnetwork_ip_ranges_to_nat == "LIST_OF_SUBNETWORKS"
    error_message = "Cloud NAT must be on by default, named from the VPC, and scoped to an explicit subnet list (public tier excluded)."
  }

  assert {
    condition     = length(module.network.internet_egress_route) == 1 && module.network.internet_egress_route[0].dest_range == "0.0.0.0/0" && module.network.internet_egress_route[0].next_hop_gateway == "default-internet-gateway"
    error_message = "With Cloud NAT on, the spoke must get a 0.0.0.0/0 route to the default internet gateway (tiered-vpc deletes the default route)."
  }

  assert {
    condition     = output.private_service_access_range_name == "google-managed-services" && length(module.private_service_connect) == 1
    error_message = "PSA (google-managed-services) and PSC must be on by default."
  }

  assert {
    condition     = module.cloud_armor[0].policy_name == "mock-dev-security-policy"
    error_message = "The Cloud Armor edge policy must be on by default, named <project_prefix>-security-policy."
  }

  assert {
    condition     = length(module.vpc_flow_logs) == 0 && length(module.flow_logs_kms) == 0 && output.vpc_flow_logs_sink_name == null
    error_message = "Flow-log export must be opt-in."
  }

  assert {
    condition     = length(module.vpc_peering) == 0 && length(module.dns) == 0 && length(module.vpc_service_controls) == 0 && length(module.additional_firewall_rules) == 0
    error_message = "Peering, DNS, VPC-SC and additional firewall rules must be absent unless configured."
  }
}

run "hub_peering_and_dns_peering_zone" {
  command = plan

  variables {
    labels = { env = "dev" }
    peerings = {
      "hub-peering" = {
        peer_network         = "projects/hub/global/networks/hub-vpc-core"
        export_custom_routes = true
        import_custom_routes = true
      }
    }
    dns_zones = {
      "internal-peering" = {
        dns_name        = "internal.example.com."
        visibility      = "private"
        description     = "Peering zone to resolve internal hub DNS"
        peering_network = "projects/hub/global/networks/hub-vpc-core"
        dnssec_enabled  = true
      }
    }
  }

  assert {
    condition     = keys(module.vpc_peering) == ["hub-peering"]
    error_message = "One peering must be planned per peerings entry, keyed by name."
  }

  assert {
    condition     = module.dns["internal-peering"].zone.visibility == "private" && module.dns["internal-peering"].zone.dns_name == "internal.example.com."
    error_message = "The DNS peering zone must be private and keep the hub domain."
  }

  assert {
    condition     = length(module.dns["internal-peering"].zone.cloud_logging_config) == 1 && module.dns["internal-peering"].zone.labels == tomap({ env = "dev" })
    error_message = "DNS query logging must be forced on and labels must propagate."
  }
}

run "flow_logs_export_to_cmek_bigquery" {
  command = plan

  variables {
    flow_logs_export = {
      enabled                 = true
      create_bigquery_dataset = true
      bigquery_dataset_id     = "vpc_flow_logs_dev"
      bigquery_location       = "europe-west1"
      retention_days          = 30
    }
  }

  assert {
    condition     = length(module.flow_logs_kms) == 1 && length(module.vpc_flow_logs) == 1
    error_message = "Enabling export must plan the CMEK keyring and the flow-log sink."
  }

  assert {
    condition     = module.vpc_flow_logs[0].destination == "bigquery.googleapis.com/projects/mock-host-project/datasets/vpc_flow_logs_dev"
    error_message = "The sink destination must be derived from the created BigQuery dataset."
  }
}

run "optional_services_can_be_disabled" {
  command = plan

  variables {
    deletion_protection     = true
    nat                     = { enabled = false }
    private_service_access  = { enabled = false }
    private_service_connect = { enabled = false }
    edge                    = { cloud_armor = { enabled = false } }
    firewall = {
      enable_iap_access = false
      additional_rules = {
        "allow-internal" = {
          source_ranges = ["10.0.0.0/8"]
          allow_rules   = [{ protocol = "tcp", ports = ["443"] }]
        }
      }
    }
  }

  assert {
    condition     = length(module.integrated_nat) == 0 && output.nat_ip == null
    error_message = "nat.enabled = false must drop Cloud NAT and null the nat_ip output."
  }

  assert {
    condition     = length(module.network.internet_egress_route) == 0
    error_message = "nat.enabled = false must not create the internet egress route."
  }

  assert {
    condition     = length(module.private_service_access) == 0 && output.private_service_access_range_name == null && length(module.private_service_connect) == 0
    error_message = "PSA and PSC must be droppable."
  }

  assert {
    condition     = length(module.cloud_armor) == 0 && output.security_policy_id == null
    error_message = "edge.cloud_armor.enabled = false must drop the policy and null its outputs."
  }

  assert {
    condition     = keys(module.additional_firewall_rules) == ["allow-internal"] && module.additional_firewall_rules["allow-internal"].name == "allow-internal"
    error_message = "firewall.additional_rules must plan one VPC firewall rule per entry."
  }

  assert {
    condition     = length(module.network.subnets.private) == 2
    error_message = "Disabling services must not touch the network core."
  }
}

run "firewall_mode_defaults_to_legacy" {
  command = plan

  assert {
    condition     = output.firewall_policy_name == null && length(module.network.vpc) > 0
    error_message = "firewall_mode must default to legacy: no network firewall policy, unchanged plan."
  }
}

run "firewall_mode_policy_passes_through" {
  command = plan

  variables {
    firewall_mode                     = "policy"
    firewall_policy_enforcement_order = "BEFORE_CLASSIC_FIREWALL"
  }

  assert {
    condition     = output.firewall_policy_name == "mock-dev-vpc-tier-policy"
    error_message = "firewall_mode must reach network/tiered-vpc, which then plans the <name>-tier-policy network firewall policy."
  }
}

run "firewall_policy_fields_pass_through" {
  command = plan

  variables {
    firewall_mode                     = "both"
    firewall_policy_enforcement_order = "AFTER_CLASSIC_FIREWALL"
    firewall = {
      api_gateway_source_ranges               = ["10.200.0.0/24"]
      database_egress_target_service_accounts = ["db@mock-project.iam.gserviceaccount.com"]
    }
  }

  assert {
    condition     = module.network.firewall_policy_rules["apigateway-to-public"].src_ip_ranges == tolist(["10.200.0.0/24"]) && module.network.firewall_policy_rules["database-deny-egress"].target_service_accounts == tolist(["db@mock-project.iam.gserviceaccount.com"])
    error_message = "firewall.api_gateway_source_ranges and firewall.database_egress_target_service_accounts must reach network/tiered-vpc."
  }
}

run "firewall_policy_fields_default_to_current_behaviour" {
  command = plan

  variables {
    firewall_mode = "both"
  }

  assert {
    condition     = !contains(keys(module.network.firewall_policy_rules), "apigateway-to-public") && module.network.firewall_policy_rules["database-deny-egress"].target_service_accounts == null
    error_message = "Unset, the new firewall fields must keep the defaults: no API Gateway policy rule and no egress target service accounts."
  }
}

run "no_additional_regions_unchanged" {
  command = plan

  assert {
    condition     = length(module.additional_region_nat) == 0 && output.additional_region_subnets == {} && output.additional_region_routers == {}
    error_message = "additional_regions = {} (default) must plan no additional-region subnets, routers or NAT."
  }

  assert {
    condition     = length(module.integrated_nat) == 1 && module.integrated_nat[0].router_name == "mock-dev-vpc-router" && module.integrated_nat[0].region == "europe-west1"
    error_message = "The primary router and NAT must keep their unkeyed address, name and region."
  }
}

run "second_region_subnets_router_nat" {
  command = plan

  variables {
    nat = {
      log_filter = "ALL"
    }
    additional_regions = {
      "us-east4" = {
        subnet_cidrs = { public = "10.200.0.0/24", private = "10.200.16.0/24", database = "10.200.32.0/24" }
      }
      "us-west1" = {
        subnet_cidrs = { public = "10.201.0.0/24", private = "10.201.16.0/24", database = "10.201.32.0/24" }
        nat          = false
      }
    }
  }

  assert {
    condition     = toset(keys(output.additional_region_subnets)) == toset(["us-east4", "us-west1"]) && output.additional_region_subnets["us-east4"].private.subnet.region == "us-east4" && output.additional_region_subnets["us-east4"].private.subnet.name == "mock-dev-vpc-private-us-east4"
    error_message = "Each additional region must get its own regional tier subnets."
  }

  assert {
    condition     = toset(keys(module.additional_region_nat)) == toset(["us-east4"]) && output.additional_region_routers == { "us-east4" = "mock-dev-vpc-router-us-east4" }
    error_message = "A router and NAT must be planned only for additional regions with nat = true, named <network>-router-<region>."
  }

  assert {
    condition     = module.additional_region_nat["us-east4"].region == "us-east4" && module.additional_region_nat["us-east4"].nat.name == "mock-dev-vpc-nat-us-east4" && module.additional_region_nat["us-east4"].nat.log_config[0].filter == "ALL" && module.additional_region_nat["us-east4"].nat.source_subnetwork_ip_ranges_to_nat == "LIST_OF_SUBNETWORKS"
    error_message = "The additional-region NAT must be in its region, named <network>-nat-<region>, with the primary nat settings and a subnet list (private and database tiers only)."
  }

  assert {
    condition     = length(module.integrated_nat) == 1 && module.integrated_nat[0].router_name == "mock-dev-vpc-router" && module.integrated_nat[0].region == "europe-west1"
    error_message = "The primary router and NAT must be unchanged by additional regions."
  }
}

run "additional_region_nat_off_when_nat_disabled" {
  command = plan

  variables {
    nat = {
      enabled = false
    }
    additional_regions = {
      "us-east4" = {
        subnet_cidrs = { public = "10.200.0.0/24", private = "10.200.16.0/24", database = "10.200.32.0/24" }
      }
    }
  }

  assert {
    condition     = length(module.additional_region_nat) == 0 && length(module.integrated_nat) == 0 && length(output.additional_region_subnets) == 1
    error_message = "nat.enabled = false must suppress every NAT, additional regions included."
  }
}
