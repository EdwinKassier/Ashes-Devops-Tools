# Plan assertions for stages/net-hub (mock providers, no credentials).

mock_provider "google" {
  mock_data "google_compute_zones" {
    defaults = {
      names = ["us-central1-a", "us-central1-b"]
    }
  }
}
mock_provider "google-beta" {}

variables {
  project_id     = "mock-hub-project"
  project_prefix = "mock"
  region         = "us-central1"
  network = {
    name       = "hub-vpc-core"
    cidr_block = "10.0.0.0/16"
  }
}

run "defaults_build_a_shared_vpc_hub" {
  command = plan

  assert {
    condition     = output.network_name == "hub-vpc-core" && toset(keys(output.subnets.private)) == toset(["us-central1-a", "us-central1-b"])
    error_message = "With no explicit zones the hub must lay out one subnet per discovered zone."
  }

  assert {
    condition     = output.subnets.private["us-central1-a"].ip_cidr_range == "10.0.16.0/24"
    error_message = "Hub subnet CIDRs must follow the tiered-vpc derivation."
  }

  assert {
    condition     = length(module.integrated_nat) == 1 && module.integrated_nat[0].router_name == "hub-vpc-core-router"
    error_message = "The hub must have Cloud NAT and its router by default."
  }

  assert {
    condition     = output.private_service_access_range_name == "google-managed-services" && length(module.private_service_connect) == 1
    error_message = "PSA and PSC must be on by default in the hub."
  }

  assert {
    condition     = length(module.vpn) == 0 && length(module.interconnects) == 0 && output.vpn_gateway_ips == null
    error_message = "Hybrid connectivity must be opt-in."
  }

  assert {
    condition     = length(module.hierarchical_firewall_policies) == 0 && length(module.vpc_service_controls) == 0
    error_message = "No hierarchical firewall policy or perimeter unless configured."
  }
}

run "hierarchical_policy_and_perimeter" {
  command = plan

  variables {
    hierarchical_firewall_policies = {
      "policy-hub-shared" = {
        parent       = "folders/111111111"
        associations = ["folders/111111111", "folders/222222222"]
        rules = [{
          priority       = 500
          action         = "deny"
          direction      = "INGRESS"
          layer4_configs = [{ ip_protocol = "tcp", ports = ["22", "3389"] }]
          src_ip_ranges  = ["0.0.0.0/0"]
        }]
      }
    }
    vpc_service_controls = {
      "hub_data_perimeter" = {
        organization_id     = "organizations/123456789"
        access_policy_name  = "1234567890"
        perimeter_title     = "Hub Network Data Protection Perimeter"
        protected_projects  = ["111111111111"]
        restricted_services = ["storage.googleapis.com"]
        enable_dry_run      = false
      }
    }
  }

  assert {
    condition     = keys(module.hierarchical_firewall_policies) == ["policy-hub-shared"]
    error_message = "One hierarchical firewall policy must be planned per entry, keyed by name."
  }

  assert {
    condition     = keys(module.vpc_service_controls) == ["hub_data_perimeter"]
    error_message = "One perimeter must be planned per vpc_service_controls entry."
  }
}

run "ha_vpn_and_interconnect" {
  command = plan

  variables {
    vpn = {
      enabled          = true
      peer_gateway_ips = ["203.0.113.1", "203.0.113.2"]
    }
    vpn_shared_secret = "mock-psk-not-a-secret"
    interconnects = {
      "ic-partner-1" = {
        region      = "us-central1"
        router_name = "hub-ic-router"
      }
    }
  }

  assert {
    condition     = length(module.vpn) == 1 && keys(module.interconnects) == ["ic-partner-1"]
    error_message = "Enabling VPN and declaring an interconnect must plan both."
  }
}

run "optional_services_can_be_disabled" {
  command = plan

  variables {
    deletion_protection     = true
    nat                     = { enabled = false }
    private_service_access  = { enabled = false }
    private_service_connect = { enabled = false }
  }

  assert {
    condition     = length(module.integrated_nat) == 0 && output.nat_ip == null && length(module.private_service_access) == 0 && length(module.private_service_connect) == 0
    error_message = "NAT, PSA and PSC must each be droppable."
  }
}
