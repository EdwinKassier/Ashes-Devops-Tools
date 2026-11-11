# Egress (Cloud NAT tiers, hub proxy PSC endpoint) and Cloud NAT alerts for
# stages/net-spoke (mock providers, no credentials).

mock_provider "google" {
  mock_data "google_compute_zones" {
    defaults = {
      names = ["europe-west1-b", "europe-west1-c"]
    }
  }
  mock_data "google_project" {
    defaults = {
      number = "123456789012"
    }
  }
  mock_resource "google_compute_address" {
    defaults = {
      address = "10.10.16.50"
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

run "nat_private_tier_only_by_default" {
  command = apply

  assert {
    condition     = output.nat_subnet_tiers == tolist(["private"]) && length(module.integrated_nat[0].nat.subnetwork) == 2
    error_message = "Cloud NAT must translate the private tier only by default (no internet path from the database tier)."
  }

  assert {
    condition     = length(google_compute_forwarding_rule.egress_proxy) == 0 && output.egress_proxy_address == null
    error_message = "The hub proxy endpoint must be opt-in."
  }
}

run "database_tier_natted_on_request" {
  command = apply

  variables {
    nat = { include_database_subnets = true }
    additional_regions = {
      "europe-west4" = {
        subnet_cidrs = { public = "10.10.100.0/24", private = "10.10.101.0/24", database = "10.10.102.0/24" }
      }
    }
  }

  assert {
    condition     = output.nat_subnet_tiers == tolist(["private", "database"]) && length(module.integrated_nat[0].nat.subnetwork) == 4
    error_message = "nat.include_database_subnets must add the database subnets to the NAT."
  }

  assert {
    condition     = length(module.additional_region_nat["europe-west4"].nat.subnetwork) == 2
    error_message = "The additional-region NAT must follow the same tier selection."
  }
}

run "egress_proxy_replaces_private_nat" {
  command = apply

  variables {
    egress_proxy = {
      enabled            = true
      service_attachment = "projects/mock-hub-project/regions/europe-west1/serviceAttachments/hub-vpc-core-swp-psc"
    }
  }

  assert {
    condition     = length(module.integrated_nat) == 0 && length(output.nat_subnet_tiers) == 0
    error_message = "With the hub proxy and no database NAT, the spoke must have no Cloud NAT."
  }

  assert {
    condition = (
      google_compute_forwarding_rule.egress_proxy[0].target == "projects/mock-hub-project/regions/europe-west1/serviceAttachments/hub-vpc-core-swp-psc" &&
      google_compute_forwarding_rule.egress_proxy[0].load_balancing_scheme == "" &&
      google_compute_address.egress_proxy[0].address_type == "INTERNAL"
    )
    error_message = "The spoke must get a PSC endpoint (internal address + forwarding rule) targeting the hub proxy."
  }

  assert {
    condition     = output.egress_proxy_address == "10.10.16.50"
    error_message = "egress_proxy_address must expose the endpoint address."
  }

  assert {
    condition     = length(module.nat_alerts) == 0
    error_message = "No NAT, no NAT alerts."
  }
}

run "egress_proxy_can_keep_private_nat" {
  command = plan

  variables {
    egress_proxy = {
      enabled            = true
      service_attachment = "projects/mock-hub-project/regions/europe-west1/serviceAttachments/hub-vpc-core-swp-psc"
    }
    nat = { include_private_subnets = true }
  }

  assert {
    condition     = length(module.integrated_nat) == 1 && output.nat_subnet_tiers == tolist(["private"])
    error_message = "nat.include_private_subnets = true must keep the private-tier NAT next to the proxy endpoint."
  }
}

run "nat_alerts_on_by_default" {
  command = apply

  variables {
    alerting = { notification_channel_ids = ["projects/mock-host-project/notificationChannels/123"] }
  }

  assert {
    condition     = toset(keys(output.nat_alert_policy_ids)) == toset(["nat_allocation_failed", "nat_dropped_packets"])
    error_message = "A spoke with Cloud NAT must get the NAT alerts by default."
  }

  assert {
    condition     = module.nat_alerts[0].all_notification_channel_ids == ["projects/mock-host-project/notificationChannels/123"]
    error_message = "The NAT alerts must use the supplied notification channels."
  }
}

run "nat_alerts_can_be_turned_off" {
  command = plan

  variables {
    alerting = { enabled = false }
  }

  assert {
    condition     = length(module.nat_alerts) == 0
    error_message = "alerting.enabled = false must create no alert policies."
  }
}
