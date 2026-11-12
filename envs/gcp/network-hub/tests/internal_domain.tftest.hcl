# The internal DNS domain (var.internal_domain > gcp.network.internal_domain >
# internal.local) reaches the network-hub stage, which names the internal-root
# private zone after it. The stage is overridden here: the root's job is to hand
# it the effective value, which local.internal_domain exposes. The stage's own
# suites assert the zone name, and gcp-workload's contracts suite asserts that
# its internal-peering zone follows hub_network.dns_domain.

mock_provider "google" {}
mock_provider "google-beta" {}
mock_provider "random" {}

variables {
  project_prefix         = "acme"
  hub_vpc_cidr_block     = "10.0.0.0/16"
  dns_hub_vpc_cidr_block = "10.1.0.0/16"
  environments = {
    dev = {
      display_name            = "Development"
      region                  = "europe-west1"
      cidr_block              = "10.10.0.0/16"
      budget_monthly_limit    = 100
      iam_group_role_bindings = {}
    }
  }
}

override_data {
  target = data.terraform_remote_state.gcp_organization
  values = {
    outputs = {
      contract = {
        org_id  = "123456789012"
        folders = { dev = { id = "folders/111", display_name = "Development" } }
      }
    }
  }
}

override_data {
  target = data.terraform_remote_state.gcp_projects
  values = {
    outputs = {
      contract = {
        project_ids     = { "shared-hub" = "acme-hub-abcd", "shared-dns" = "acme-dns-abcd", "dev-host" = "acme-dev-host-abcd" }
        project_numbers = { "shared-hub" = "111111111111", "shared-dns" = "222222222222", "dev-host" = "333333333333" }
      }
    }
  }
}

override_module {
  target = module.network_hub
  outputs = {
    hub_vpc_self_link = "https://www.googleapis.com/compute/v1/projects/acme-hub-abcd/global/networks/acme-hub-vpc"
    hub_vpc_name      = "acme-hub-vpc"
    dns_zone_name     = "hub-dns"
    hub_dns_domain    = "hub.internal."
  }
}

run "default_is_internal_local" {
  command = plan

  variables {
    landing_zone_config_path = ""
  }

  assert {
    condition     = local.internal_domain == "internal.local"
    error_message = "With no variable and no config the internal domain must stay internal.local, so an existing estate's zone does not change."
  }
}

run "domain_from_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-internal-domain.yaml"
  }

  assert {
    condition     = local.internal_domain == "corp.example.com"
    error_message = "gcp.network.internal_domain must reach the network-hub stage as the effective internal domain."
  }
}

run "variable_beats_config" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-internal-domain.yaml"
    internal_domain          = "vars.example.org"
  }

  assert {
    condition     = local.internal_domain == "vars.example.org"
    error_message = "An explicit internal_domain variable must replace the config value."
  }
}

run "rejects_trailing_dot" {
  command = plan

  variables {
    landing_zone_config_path = ""
    internal_domain          = "corp.example.com."
  }

  expect_failures = [var.internal_domain]
}

run "rejects_uppercase" {
  command = plan

  variables {
    landing_zone_config_path = ""
    internal_domain          = "Corp.Example.com"
  }

  expect_failures = [var.internal_domain]
}

run "rejects_single_label" {
  command = plan

  variables {
    landing_zone_config_path = ""
    internal_domain          = "corp"
  }

  expect_failures = [var.internal_domain]
}

run "rejects_invalid_config_value" {
  command = plan

  variables {
    landing_zone_config_path = "../../../config/tests/internal-domain-invalid.yaml"
  }

  expect_failures = [var.internal_domain]
}
