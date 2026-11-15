# Forwarding zones send queries for their suffix to target name servers.
# forwarding_path = "private" routes them through the VPC (VPN/Interconnect),
# which on-premises targets outside RFC 1918 need.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id                  = "mock-project"
  zone_name                   = "fwd-corp"
  dns_name                    = "corp.example.com."
  visibility                  = "private"
  private_visibility_networks = ["projects/mock-project/global/networks/hub-vpc"]
  forwarding_targets          = ["192.168.0.10", "192.168.0.11"]
}

run "forwarding_targets_use_the_provider_default_path" {
  command = plan

  assert {
    condition = (
      length(google_dns_managed_zone.private_zone[0].forwarding_config[0].target_name_servers) == 2 &&
      alltrue([for t in google_dns_managed_zone.private_zone[0].forwarding_config[0].target_name_servers : t.forwarding_path == null || t.forwarding_path == ""])
    )
    error_message = "Without forwarding_path the targets keep the provider default path."
  }
}

run "private_forwarding_path_reaches_every_target" {
  command = plan

  variables {
    forwarding_path = "private"
  }

  assert {
    condition     = alltrue([for t in google_dns_managed_zone.private_zone[0].forwarding_config[0].target_name_servers : t.forwarding_path == "private"])
    error_message = "forwarding_path = private must apply to every target name server."
  }
}

run "rejects_unknown_forwarding_path" {
  command = plan

  variables {
    forwarding_path = "internet"
  }

  expect_failures = [var.forwarding_path]
}
