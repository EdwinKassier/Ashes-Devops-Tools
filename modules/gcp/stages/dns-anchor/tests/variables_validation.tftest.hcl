# Input validation for stages/dns-anchor (mock providers, no credentials).

mock_provider "google" {
  mock_data "google_compute_zones" {
    defaults = {
      names = ["us-central1-a"]
    }
  }
}
mock_provider "google-beta" {}

variables {
  project_id = "mock-dns-project"
  region     = "us-central1"
  network = {
    name       = "dns-vpc-core"
    cidr_block = "10.1.0.0/16"
  }
}

run "accepts_valid_inputs" {
  command = plan
}

# Two-digit GCP regions (europe-west10, europe-west12) and their zones are valid.
run "accepts_two_digit_region_zones" {
  command = plan
  variables {
    region = "europe-west10"
    network = {
      name           = "dns-vpc-core"
      cidr_block     = "10.1.0.0/16"
      explicit_zones = ["europe-west10-a", "europe-west10-b"]
    }
  }
}

run "rejects_invalid_region" {
  command = plan
  variables {
    region = "nowhere"
  }
  expect_failures = [var.region]
}

run "rejects_invalid_cidr" {
  command = plan
  variables {
    network = { name = "dns-vpc-core", cidr_block = "300.1.0.0/16" }
  }
  expect_failures = [var.network]
}

run "rejects_unqualified_dns_name" {
  command = plan
  variables {
    dns_zones = { "internal-root" = { dns_name = "internal.example.com" } }
  }
  expect_failures = [var.dns_zones]
}
