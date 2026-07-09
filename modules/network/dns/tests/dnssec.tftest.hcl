# Regression test: when dnssec_enabled = false the public zone must set
# dnssec_config.state = "off" (not "transfer", which keeps signing active).
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id = "mock-project"
  zone_name  = "test-zone"
  dns_name   = "public.example.com."
  visibility = "public"
}

run "dnssec_disabled_sets_state_off" {
  command = plan

  variables {
    dnssec_enabled = false
  }

  assert {
    condition     = google_dns_managed_zone.public_zone[0].dnssec_config[0].state == "off"
    error_message = "dnssec_config.state must be 'off' when dnssec_enabled is false"
  }
}

run "dnssec_enabled_sets_state_on" {
  command = plan

  variables {
    dnssec_enabled = true
  }

  assert {
    condition     = google_dns_managed_zone.public_zone[0].dnssec_config[0].state == "on"
    error_message = "dnssec_config.state must be 'on' when dnssec_enabled is true"
  }
}
