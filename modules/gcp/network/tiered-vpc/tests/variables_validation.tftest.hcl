# Input validation for network/tiered-vpc (mock providers, no credentials).

mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  project_id = "mock-project"
  name       = "mock-vpc"
  region     = "us-central1"
  cidr_block = "10.0.0.0/16"
  zones      = ["us-central1-a"]
}

run "accepts_valid_inputs" {
  command = plan
}

run "rejects_invalid_project_id" {
  command = plan
  variables {
    project_id = "Bad_Project"
  }
  expect_failures = [var.project_id]
}

run "rejects_invalid_vpc_name" {
  command = plan
  variables {
    name = "1-starts-with-digit"
  }
  expect_failures = [var.name]
}

run "rejects_invalid_region" {
  command = plan
  variables {
    region = "uscentral"
  }
  expect_failures = [var.region]
}

run "rejects_invalid_cidr" {
  command = plan
  variables {
    cidr_block = "not-a-cidr"
  }
  expect_failures = [var.cidr_block]
}

run "rejects_cidr_with_host_bits" {
  command = plan
  variables {
    cidr_block = "10.0.1.0/16"
  }
  expect_failures = [var.cidr_block]
}

run "rejects_empty_zones" {
  command = plan
  variables {
    zones = []
  }
  expect_failures = [var.zones]
}

run "rejects_invalid_flow_log_interval" {
  command = plan
  variables {
    flow_logs = { aggregation_interval = "INTERVAL_2_SEC" }
  }
  expect_failures = [var.flow_logs]
}

run "rejects_out_of_range_flow_log_sampling" {
  command = plan
  variables {
    flow_logs = { sampling = 1.5 }
  }
  expect_failures = [var.flow_logs]
}

run "rejects_cidr_list_shorter_than_zones" {
  command = plan

  variables {
    zones = ["us-central1-a", "us-central1-b"]
    subnet_cidrs = {
      public = ["10.0.0.0/24"]
    }
  }

  expect_failures = [var.subnet_cidrs]
}
