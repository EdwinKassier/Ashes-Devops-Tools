# Input validation for modules/gcp/network/secure-web-proxy. mock_provider: no
# GCP credentials needed.

mock_provider "google" {}

variables {
  project_id = "mock-hub-project"
  name       = "hub-swp"
  region     = "us-central1"
  network    = "projects/mock-hub-project/global/networks/hub-vpc"
  subnetwork = "projects/mock-hub-project/regions/us-central1/subnetworks/hub-private"
}

run "rejects_invalid_project_id" {
  command = plan
  variables {
    project_id = "X"
  }
  expect_failures = [var.project_id]
}

run "rejects_invalid_name" {
  command = plan
  variables {
    name = "Hub_SWP"
  }
  expect_failures = [var.name]
}

run "rejects_network_self_link_form" {
  command = plan
  variables {
    network = "https://www.googleapis.com/compute/v1/projects/p/global/networks/hub"
  }
  expect_failures = [var.network]
}

run "rejects_subnetwork_name_only" {
  command = plan
  variables {
    subnetwork = "hub-private"
  }
  expect_failures = [var.subnetwork]
}

run "rejects_out_of_range_port" {
  command = plan
  variables {
    ports = [70000]
  }
  expect_failures = [var.ports]
}

run "rejects_empty_ports" {
  command = plan
  variables {
    ports = []
  }
  expect_failures = [var.ports]
}

run "rejects_unknown_routing_mode" {
  command = plan
  variables {
    routing_mode = "TRANSPARENT"
  }
  expect_failures = [var.routing_mode]
}

run "rejects_fqdn_with_scheme" {
  command = plan
  variables {
    allowed_fqdns = ["https://example.com"]
  }
  expect_failures = [var.allowed_fqdns]
}

run "rejects_rule_with_unknown_action" {
  command = plan
  variables {
    additional_rules = { r1 = { priority = 10, action = "LOG", session_matcher = "true" } }
  }
  expect_failures = [var.additional_rules]
}

run "rejects_rule_on_allowlist_priority" {
  command = plan
  variables {
    additional_rules = { r1 = { priority = 1000, action = "DENY", session_matcher = "true" } }
  }
  expect_failures = [var.additional_rules]
}

run "rejects_duplicate_rule_priorities" {
  command = plan
  variables {
    additional_rules = {
      r1 = { priority = 10, action = "DENY", session_matcher = "true" }
      r2 = { priority = 10, action = "ALLOW", session_matcher = "true" }
    }
  }
  expect_failures = [var.additional_rules]
}

run "rejects_proxy_only_subnet_without_cidr" {
  command = plan
  variables {
    create_proxy_only_subnet = true
  }
  expect_failures = [var.proxy_only_subnet_cidr]
}

run "rejects_invalid_proxy_only_cidr" {
  command = plan
  variables {
    create_proxy_only_subnet = true
    proxy_only_subnet_cidr   = "10.0.254.0"
  }
  expect_failures = [var.proxy_only_subnet_cidr]
}

run "rejects_service_attachment_in_next_hop_mode" {
  command = plan
  variables {
    routing_mode              = "NEXT_HOP_ROUTING_MODE"
    create_service_attachment = true
    psc_nat_subnet_cidr       = "10.0.253.0/24"
    consumer_accept_projects  = ["111111111111"]
  }
  expect_failures = [var.create_service_attachment]
}

run "rejects_service_attachment_without_nat_subnet" {
  command = plan
  variables {
    create_service_attachment = true
    consumer_accept_projects  = ["111111111111"]
  }
  expect_failures = [var.psc_nat_subnet_cidr]
}

run "rejects_service_attachment_without_consumers" {
  command = plan
  variables {
    create_service_attachment = true
    psc_nat_subnet_cidr       = "10.0.253.0/24"
  }
  expect_failures = [var.consumer_accept_projects]
}

run "rejects_zero_connection_limit" {
  command = plan
  variables {
    consumer_connection_limit = 0
  }
  expect_failures = [var.consumer_connection_limit]
}
