# Input-validation suite: each run supplies one invalid input and expects the
# matching variable validation to fail at plan time.

mock_provider "google" {}

variables {
  project_id             = "acme-host-abcd"
  region                 = "europe-west1"
  name                   = "my-api"
  domains                = ["api.example.com"]
  cloud_run_service_name = "my-api"
}

run "rejects_empty_domains" {
  command = plan

  variables {
    domains = []
  }

  expect_failures = [var.domains]
}

run "rejects_non_fqdn_domain" {
  command = plan

  variables {
    domains = ["not a domain"]
  }

  expect_failures = [var.domains]
}

run "rejects_bad_project_id" {
  command = plan

  variables {
    project_id = "X"
  }

  expect_failures = [var.project_id]
}

run "rejects_bad_region" {
  command = plan

  variables {
    region = "europe_west_1"
  }

  expect_failures = [var.region]
}

run "rejects_empty_service_name" {
  command = plan

  variables {
    cloud_run_service_name = "  "
  }

  expect_failures = [var.cloud_run_service_name]
}

run "rejects_out_of_range_ttl" {
  command = plan

  variables {
    dns_managed_zone = "app-zone"
    dns_ttl          = 99999
  }

  expect_failures = [var.dns_ttl]
}
