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
