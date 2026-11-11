# Egress (Cloud NAT tiers, Secure Web Proxy) and data-plane alerts for
# stages/net-hub (mock providers, no credentials).

mock_provider "google" {
  mock_data "google_compute_zones" {
    defaults = {
      names = ["us-central1-a", "us-central1-b"]
    }
  }
  # Valid-form IDs so apply-mode runs pass the proxy module's input checks.
  mock_resource "google_compute_network" {
    defaults = {
      id = "projects/mock-hub-project/global/networks/hub-vpc-core"
    }
  }
  mock_resource "google_compute_subnetwork" {
    defaults = {
      id = "projects/mock-hub-project/regions/us-central1/subnetworks/mock-subnet"
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

run "database_tier_not_natted_by_default" {
  command = apply

  assert {
    condition     = output.nat_subnet_tiers == tolist(["private"])
    error_message = "Cloud NAT must translate the private tier only by default (no internet path from the database tier)."
  }

  assert {
    condition     = length(module.integrated_nat[0].nat.subnetwork) == 2
    error_message = "The hub NAT must list one private subnet per zone and no database subnet."
  }
}

run "database_tier_natted_on_request" {
  command = apply

  variables {
    nat = { include_database_subnets = true }
  }

  assert {
    condition     = output.nat_subnet_tiers == tolist(["private", "database"]) && length(module.integrated_nat[0].nat.subnetwork) == 4
    error_message = "nat.include_database_subnets must add the database subnets to the NAT."
  }
}

run "secure_web_proxy_off_by_default" {
  command = plan

  assert {
    condition     = length(module.secure_web_proxy) == 0 && output.secure_web_proxy == null
    error_message = "The Secure Web Proxy must be opt-in."
  }
}

run "secure_web_proxy_with_psc_publishing" {
  command = apply

  variables {
    secure_web_proxy = {
      enabled                  = true
      allowed_fqdns            = ["*.github.com", "pypi.org"]
      proxy_only_subnet_cidr   = "10.0.254.0/23"
      psc_nat_subnet_cidr      = "10.0.253.0/24"
      consumer_accept_projects = ["333333333333"]
    }
  }

  assert {
    condition     = length(module.secure_web_proxy) == 1 && module.secure_web_proxy[0].gateway_ports == tolist([443])
    error_message = "secure_web_proxy.enabled must plan one proxy on port 443."
  }

  assert {
    condition     = module.secure_web_proxy[0].url_list_id != null && module.secure_web_proxy[0].proxy_only_subnet_id != null
    error_message = "The allowlist URL list and the proxy-only subnet must be created."
  }

  assert {
    condition     = output.secure_web_proxy.service_attachment_id != null && output.secure_web_proxy.ports == tolist([443])
    error_message = "psc_nat_subnet_cidr must publish the proxy through a service attachment."
  }
}

run "secure_web_proxy_name_fits_long_network_names" {
  command = plan

  variables {
    network = {
      name       = "a-very-long-hub-network-name-for-test-01"
      cidr_block = "10.0.0.0/16"
    }
    secure_web_proxy = { enabled = true }
  }

  assert {
    condition     = length(module.secure_web_proxy) == 1
    error_message = "A long hub network name must still give a valid proxy name."
  }
}

run "nat_alerts_on_by_default" {
  command = apply

  variables {
    alerting = { notification_channel_ids = ["projects/mock-hub-project/notificationChannels/123"] }
  }

  assert {
    condition     = toset(keys(output.network_alert_policy_ids)) == toset(["nat_allocation_failed", "nat_dropped_packets"])
    error_message = "With Cloud NAT on (and no VPN or interconnect), the hub must get the two NAT alerts by default."
  }

  assert {
    condition     = module.network_alerts[0].all_notification_channel_ids == ["projects/mock-hub-project/notificationChannels/123"]
    error_message = "The hub alerts must use the supplied notification channels."
  }
}

run "vpn_and_interconnect_turn_on_tunnel_and_bgp_alerts" {
  command = apply

  variables {
    vpn = {
      enabled          = true
      peer_gateway_ips = ["203.0.113.1", "203.0.113.2"]
    }
    vpn_shared_secret_wo = "mock-psk-not-a-secret"
  }

  assert {
    condition     = toset(keys(output.network_alert_policy_ids)) == toset(["vpn_tunnel_down", "bgp_session_down", "nat_allocation_failed", "nat_dropped_packets"])
    error_message = "VPN must add the tunnel and BGP alerts next to the NAT ones."
  }
}

run "interconnect_only_gets_bgp_alert" {
  command = apply

  variables {
    nat = { enabled = false }
    interconnects = {
      "ic-partner-1" = {
        region      = "us-central1"
        router_name = "hub-ic-router"
      }
    }
  }

  assert {
    condition     = keys(output.network_alert_policy_ids) == ["bgp_session_down"]
    error_message = "An interconnect alone must add only the BGP alert."
  }
}

run "no_watched_feature_no_alerts" {
  command = plan

  variables {
    nat = { enabled = false }
  }

  assert {
    condition     = length(module.network_alerts) == 0
    error_message = "With no NAT, VPN or interconnect there is nothing to alert on."
  }
}

run "alerting_can_be_turned_off" {
  command = plan

  variables {
    alerting = { enabled = false }
  }

  assert {
    condition     = length(module.network_alerts) == 0 && output.network_alert_policy_ids == {}
    error_message = "alerting.enabled = false must create no alert policies."
  }
}
