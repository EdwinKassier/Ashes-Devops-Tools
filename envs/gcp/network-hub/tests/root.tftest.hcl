# Cross-root OUTPUT CONTRACT test for the gcp-network-hub root.
#
# gcp-workload reads hub_network (vpc_self_link / dns_domain) for spoke peering
# and internal DNS. This test overrides the upstream remote states and the
# network-hub stage with a known contract and asserts the root re-exports it.

mock_provider "google" {}
mock_provider "google-beta" {}
mock_provider "random" {}

variables {
  # Isolate the suite from any committed config/landing-zone.yaml.
  landing_zone_config_path = ""
  project_prefix           = "acme"
  hub_vpc_cidr_block       = "10.0.0.0/16"
  dns_hub_vpc_cidr_block   = "10.1.0.0/16"
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
        org_id = "123456789012"
        folders = {
          dev = { id = "folders/111", display_name = "Development" }
        }
      }
    }
  }
}

override_data {
  target = data.terraform_remote_state.gcp_projects
  values = {
    outputs = {
      contract = {
        project_ids = {
          "shared-hub" = "acme-hub-abcd"
          "shared-dns" = "acme-dns-abcd"
          "dev-host"   = "acme-dev-host-abcd"
        }
        project_numbers = {
          "shared-hub" = "111111111111"
          "shared-dns" = "222222222222"
          "dev-host"   = "333333333333"
        }
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

run "network_hub_output_contract" {
  command = plan

  assert {
    condition     = output.hub_network.vpc_self_link == "https://www.googleapis.com/compute/v1/projects/acme-hub-abcd/global/networks/acme-hub-vpc" && output.hub_network.vpc_name == "acme-hub-vpc" && output.hub_network.dns_zone_name == "hub-dns" && output.hub_network.dns_domain == "hub.internal."
    error_message = "hub_network must re-export vpc_self_link, vpc_name, dns_zone_name and dns_domain (consumed by gcp-workload)."
  }
}

# Estates with no is_production environment do not trip the prod-enforcement check.
run "no_prod_env_no_vpc_sc_warning" {
  command = plan
}

# An is_production environment with the hub perimeter missing / in dry-run warns.
run "prod_env_with_dry_run_hub_perimeter_warns" {
  command = plan

  variables {
    environments = {
      prod = {
        display_name            = "Production"
        region                  = "europe-west1"
        cidr_block              = "10.30.0.0/16"
        budget_monthly_limit    = 100
        iam_group_role_bindings = {}
        is_production           = true
      }
    }
    vpc_sc_access_policy_name = "1234567890"
    vpc_sc_enable_dry_run     = true
  }

  override_data {
    target = data.terraform_remote_state.gcp_projects
    values = {
      outputs = {
        contract = {
          project_ids     = { "shared-hub" = "acme-hub-abcd", "shared-dns" = "acme-dns-abcd", "prod-host" = "acme-prod-host-abcd" }
          project_numbers = { "shared-hub" = "111111111111", "shared-dns" = "222222222222", "prod-host" = "333333333333" }
        }
      }
    }
  }

  expect_failures = [check.hub_vpc_sc_enforced_when_prod_present]
}

# Production is the explicit is_production attribute, not a name match: an
# environment merely NAMED "prod" without the flag does not warn.
run "prod_named_env_without_flag_does_not_warn" {
  command = plan

  variables {
    environments = {
      prod = {
        display_name            = "Production"
        region                  = "europe-west1"
        cidr_block              = "10.30.0.0/16"
        budget_monthly_limit    = 100
        iam_group_role_bindings = {}
      }
    }
  }

  override_data {
    target = data.terraform_remote_state.gcp_projects
    values = {
      outputs = {
        contract = {
          project_ids     = { "shared-hub" = "acme-hub-abcd", "shared-dns" = "acme-dns-abcd", "prod-host" = "acme-prod-host-abcd" }
          project_numbers = { "shared-hub" = "111111111111", "shared-dns" = "222222222222", "prod-host" = "333333333333" }
        }
      }
    }
  }
}

# Stage contract override (FAST-style): organization_contract / projects_contract
# replace the upstream remote-state reads entirely (count = 0).
run "contracts_skip_remote_state" {
  command = plan

  variables {
    organization_contract = {
      org_id  = "123456789012"
      folders = { dev = { id = "folders/111", name = "folders/111", display_name = "Development" } }
    }
    projects_contract = {
      project_ids     = { "shared-hub" = "acme-hub-abcd", "shared-dns" = "acme-dns-abcd", "dev-host" = "acme-dev-host-abcd" }
      project_numbers = { "shared-hub" = "111111111111", "shared-dns" = "222222222222", "dev-host" = "333333333333" }
    }
  }

  assert {
    condition = (
      length(data.terraform_remote_state.gcp_organization) == 0 &&
      length(data.terraform_remote_state.gcp_projects) == 0 &&
      local.org.org_id == "123456789012" &&
      local.projects.project_ids["shared-hub"] == "acme-hub-abcd"
    )
    error_message = "supplied contracts must skip the gcp-organization / gcp-projects reads and feed the root"
  }
}

# The single `contract` output carries the same hub_network (what gcp-workload
# reads), and the deprecated alias still matches it.
run "contract_output_carries_hub_network" {
  command = plan

  assert {
    condition     = output.contract.hub_network.dns_domain == "hub.internal." && output.contract.hub_network == output.hub_network
    error_message = "output.contract must carry hub_network, identical to the deprecated hub_network alias."
  }
}

# N-1 upgrade: upstream states written before the `contract` output existed
# (individual outputs only) still plan. The fallback goes at v1.0 (UPGRADING.md).
run "pre_contract_upstream_states_still_plan" {
  command = plan

  override_data {
    target = data.terraform_remote_state.gcp_organization
    values = {
      outputs = {
        org_id  = "999999999999"
        folders = { dev = { id = "folders/111", display_name = "Development" } }
      }
    }
  }

  override_data {
    target = data.terraform_remote_state.gcp_projects
    values = {
      outputs = {
        project_ids     = { "shared-hub" = "acme-hub-abcd", "shared-dns" = "acme-dns-abcd", "dev-host" = "acme-dev-host-abcd" }
        project_numbers = { "shared-hub" = "111111111111", "shared-dns" = "222222222222", "dev-host" = "333333333333" }
      }
    }
  }

  assert {
    condition     = local.org.org_id == "999999999999" && local.projects.project_ids["shared-hub"] == "acme-hub-abcd"
    error_message = "a pre-contract upstream state (individual outputs only) must still resolve the org and projects contracts."
  }
}

# A supplied projects contract without the hub/DNS projects or an env host
# number fails on the named guard, not on a bare lookup.
run "projects_contract_missing_hub_keys_fails" {
  command = plan

  variables {
    projects_contract = {
      project_ids     = { "shared-hub" = "acme-hub-abcd" }
      project_numbers = { "shared-hub" = "111111111111" }
    }
  }

  expect_failures = [terraform_data.upstream_contract_guard]
}

# The opt-in NCC hub: off by default, so the contract carries a null hub ID and
# gcp-workload keeps peering.
run "contract_ncc_hub_null_by_default" {
  command = plan

  assert {
    condition     = local.enable_ncc_hub == false && output.contract.hub_network.ncc_hub_id == null && output.contract.hub_network.ncc_spoke_group == null
    error_message = "The NCC hub must be off by default, with a null ncc_hub_id / ncc_spoke_group in the contract."
  }
}

run "contract_carries_ncc_hub_when_enabled" {
  command = plan

  variables {
    enable_ncc_hub      = true
    ncc_preset_topology = "MESH"
  }

  override_module {
    target = module.network_hub
    outputs = {
      hub_vpc_self_link = "https://www.googleapis.com/compute/v1/projects/acme-hub-abcd/global/networks/acme-hub-vpc"
      hub_vpc_name      = "acme-hub-vpc"
      dns_zone_name     = "hub-dns"
      hub_dns_domain    = "hub.internal."
      ncc_hub_id        = "projects/acme-hub-abcd/locations/global/hubs/acme-ncc-hub"
      ncc_spoke_group   = "default"
    }
  }

  assert {
    condition     = local.enable_ncc_hub && local.ncc_preset_topology == "MESH"
    error_message = "enable_ncc_hub / ncc_preset_topology must take effect."
  }

  assert {
    condition     = output.contract.hub_network.ncc_hub_id == "projects/acme-hub-abcd/locations/global/hubs/acme-ncc-hub" && output.contract.hub_network.ncc_spoke_group == "default"
    error_message = "contract.hub_network must carry the NCC hub ID and spoke group for gcp-workload."
  }
}

run "rejects_unknown_ncc_preset_topology" {
  command = plan

  variables {
    ncc_preset_topology = "RING"
  }

  expect_failures = [var.ncc_preset_topology]
}
