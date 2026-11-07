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

run "invalid_firewall_mode" {
  command = plan

  variables {
    firewall_mode = "tags"
  }

  expect_failures = [var.firewall_mode]
}

run "invalid_firewall_policy_enforcement_order" {
  command = plan

  variables {
    firewall_policy_enforcement_order = "FIRST"
  }

  expect_failures = [var.firewall_policy_enforcement_order]
}

run "accepts_additional_region" {
  command = plan

  variables {
    additional_regions = {
      "us-east1" = { subnet_cidrs = { public = "10.1.0.0/24", private = "10.1.1.0/24", database = "10.1.2.0/24" } }
      "us-west1" = { subnet_cidrs = { public = "10.2.0.0/24", private = "10.2.1.0/24", database = "10.2.2.0/24" }, nat = false }
    }
  }
}

run "rejects_additional_region_equal_to_primary" {
  command = plan

  variables {
    additional_regions = {
      "us-central1" = { subnet_cidrs = { public = "10.1.0.0/24", private = "10.1.1.0/24", database = "10.1.2.0/24" } }
    }
  }

  expect_failures = [var.additional_regions]
}

run "rejects_invalid_additional_region_name" {
  command = plan

  variables {
    additional_regions = {
      "us-east1-b" = { subnet_cidrs = { public = "10.1.0.0/24", private = "10.1.1.0/24", database = "10.1.2.0/24" } }
    }
  }

  expect_failures = [var.additional_regions]
}

run "rejects_invalid_additional_region_cidr" {
  command = plan

  variables {
    additional_regions = {
      "us-east1" = { subnet_cidrs = { public = "10.1.0.1/24", private = "10.1.1.0/24", database = "not-a-cidr" } }
    }
  }

  expect_failures = [var.additional_regions]
}

run "rejects_additional_region_overlapping_primary" {
  command = plan

  variables {
    # 10.0.16.0/20 contains the primary private subnet 10.0.16.0/24.
    additional_regions = {
      "us-east1" = { subnet_cidrs = { public = "10.1.0.0/24", private = "10.0.16.0/20", database = "10.1.2.0/24" } }
    }
  }

  expect_failures = [var.additional_regions]
}

run "rejects_additional_regions_overlapping_each_other" {
  command = plan

  variables {
    additional_regions = {
      "us-east1" = { subnet_cidrs = { public = "10.1.0.0/24", private = "10.1.1.0/24", database = "10.1.2.0/24" } }
      "us-west1" = { subnet_cidrs = { public = "10.2.0.0/24", private = "10.1.1.128/25", database = "10.2.2.0/24" } }
    }
  }

  expect_failures = [var.additional_regions]
}

run "rejects_overlap_within_one_additional_region" {
  command = plan

  variables {
    additional_regions = {
      "us-east1" = { subnet_cidrs = { public = "10.1.0.0/24", private = "10.1.0.0/24", database = "10.1.2.0/24" } }
    }
  }

  expect_failures = [var.additional_regions]
}
