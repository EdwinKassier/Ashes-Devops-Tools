# Variable validation tests for the stages/network-hub module.
# All runs use mock_provider so no GCP credentials are required.
#
# modules/host has a data.google_compute_zones postcondition that fails with
# empty mock results, so all runs override the deeply-nested child modules via
# override_module (Terraform >= 1.9) to isolate variable validation.

mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  project_prefix         = "mock"
  hub_vpc_cidr_block     = "10.0.0.0/16"
  dns_hub_vpc_cidr_block = "10.1.0.0/16"
  default_region         = "us-central1"
  hub_project_id         = "mock-hub-project"
  dns_project_id         = "mock-dns-project"
  spoke_project_numbers  = {}
  org_id                 = "organizations/123456789"
  folders = {
    shared = {
      id           = "folders/111111111"
      name         = "folders/111111111"
      display_name = "Shared"
    }
  }
}

# ── hub_vpc_cidr_block ─────────────────────────────────────────────────────────

run "accepts_valid_hub_vpc_cidr_block" {
  command = plan

  override_module {
    target  = module.hub_network
    outputs = { network_self_link = "projects/mock-hub-project/global/networks/hub-vpc-core" }
  }
  override_module {
    target  = module.dns_hub_network
    outputs = { network_self_link = "projects/mock-dns-project/global/networks/dns-vpc-core" }
  }
  override_module {
    target  = module.dns_hub_zone
    outputs = {}
  }

  variables {
    hub_vpc_cidr_block = "10.0.0.0/16"
  }
}

run "accepts_slash_24_hub_vpc_cidr_block" {
  command = plan

  override_module {
    target  = module.hub_network
    outputs = { network_self_link = "projects/mock-hub-project/global/networks/hub-vpc-core" }
  }
  override_module {
    target  = module.dns_hub_network
    outputs = { network_self_link = "projects/mock-dns-project/global/networks/dns-vpc-core" }
  }
  override_module {
    target  = module.dns_hub_zone
    outputs = {}
  }

  variables {
    hub_vpc_cidr_block = "192.168.1.0/24"
  }
}

run "rejects_invalid_hub_vpc_cidr_block" {
  command = plan

  override_module {
    target  = module.hub_network
    outputs = { network_self_link = "projects/mock-hub-project/global/networks/hub-vpc-core" }
  }
  override_module {
    target  = module.dns_hub_network
    outputs = { network_self_link = "projects/mock-dns-project/global/networks/dns-vpc-core" }
  }
  override_module {
    target  = module.dns_hub_zone
    outputs = {}
  }

  expect_failures = [var.hub_vpc_cidr_block]

  variables {
    hub_vpc_cidr_block = "not-a-cidr"
  }
}

run "rejects_hub_vpc_cidr_without_prefix_length" {
  command = plan

  override_module {
    target  = module.hub_network
    outputs = { network_self_link = "projects/mock-hub-project/global/networks/hub-vpc-core" }
  }
  override_module {
    target  = module.dns_hub_network
    outputs = { network_self_link = "projects/mock-dns-project/global/networks/dns-vpc-core" }
  }
  override_module {
    target  = module.dns_hub_zone
    outputs = {}
  }

  expect_failures = [var.hub_vpc_cidr_block]

  variables {
    hub_vpc_cidr_block = "10.0.0.0"
  }
}

# ── dns_hub_vpc_cidr_block ─────────────────────────────────────────────────────

run "accepts_valid_dns_hub_vpc_cidr_block" {
  command = plan

  override_module {
    target  = module.hub_network
    outputs = { network_self_link = "projects/mock-hub-project/global/networks/hub-vpc-core" }
  }
  override_module {
    target  = module.dns_hub_network
    outputs = { network_self_link = "projects/mock-dns-project/global/networks/dns-vpc-core" }
  }
  override_module {
    target  = module.dns_hub_zone
    outputs = {}
  }

  variables {
    dns_hub_vpc_cidr_block = "10.1.0.0/16"
  }
}

run "rejects_invalid_dns_hub_vpc_cidr_block" {
  command = plan

  override_module {
    target  = module.hub_network
    outputs = { network_self_link = "projects/mock-hub-project/global/networks/hub-vpc-core" }
  }
  override_module {
    target  = module.dns_hub_network
    outputs = { network_self_link = "projects/mock-dns-project/global/networks/dns-vpc-core" }
  }
  override_module {
    target  = module.dns_hub_zone
    outputs = {}
  }

  expect_failures = [var.dns_hub_vpc_cidr_block]

  variables {
    dns_hub_vpc_cidr_block = "256.0.0.0/8"
  }
}

# ── org_id ─────────────────────────────────────────────────────────────────────

run "accepts_valid_org_id" {
  command = plan

  override_module {
    target  = module.hub_network
    outputs = { network_self_link = "projects/mock-hub-project/global/networks/hub-vpc-core" }
  }
  override_module {
    target  = module.dns_hub_network
    outputs = { network_self_link = "projects/mock-dns-project/global/networks/dns-vpc-core" }
  }
  override_module {
    target  = module.dns_hub_zone
    outputs = {}
  }

  variables {
    org_id = "organizations/987654321"
  }
}

run "accepts_bare_numeric_org_id" {
  # Bare numeric IDs are valid — data.google_organization.org.org_id returns this format.
  command = plan

  override_module {
    target  = module.hub_network
    outputs = { network_self_link = "projects/mock-hub-project/global/networks/hub-vpc-core" }
  }
  override_module {
    target  = module.dns_hub_network
    outputs = { network_self_link = "projects/mock-dns-project/global/networks/dns-vpc-core" }
  }
  override_module {
    target  = module.dns_hub_zone
    outputs = {}
  }

  variables {
    org_id = "123456789"
  }
}

run "rejects_org_id_with_non_numeric_suffix" {
  command = plan

  override_module {
    target  = module.hub_network
    outputs = { network_self_link = "projects/mock-hub-project/global/networks/hub-vpc-core" }
  }
  override_module {
    target  = module.dns_hub_network
    outputs = { network_self_link = "projects/mock-dns-project/global/networks/dns-vpc-core" }
  }
  override_module {
    target  = module.dns_hub_zone
    outputs = {}
  }

  expect_failures = [var.org_id]

  variables {
    org_id = "organizations/my-org"
  }
}
