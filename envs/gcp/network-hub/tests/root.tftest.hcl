# Cross-root OUTPUT CONTRACT test for the gcp-network-hub root.
#
# gcp-workload reads hub_network (vpc_self_link / dns_domain) for spoke peering
# and internal DNS. This test overrides the upstream remote states and the
# network-hub stage with a known contract and asserts the root re-exports it.

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
      org_id = "123456789012"
      folders = {
        dev = { id = "folders/111", display_name = "Development" }
      }
    }
  }
}

override_data {
  target = data.terraform_remote_state.gcp_projects
  values = {
    outputs = {
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

# SOTA M: dev-only estates do not trip the prod-enforcement check.
run "no_prod_env_no_vpc_sc_warning" {
  command = plan
}

# SOTA M: a prod environment with the hub perimeter missing / in dry-run warns.
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
      }
    }
    vpc_sc_access_policy_name = "1234567890"
    vpc_sc_enable_dry_run     = true
  }

  override_data {
    target = data.terraform_remote_state.gcp_projects
    values = {
      outputs = {
        project_ids     = { "shared-hub" = "acme-hub-abcd", "shared-dns" = "acme-dns-abcd", "prod-host" = "acme-prod-host-abcd" }
        project_numbers = { "shared-hub" = "111111111111", "shared-dns" = "222222222222", "prod-host" = "333333333333" }
      }
    }
  }

  expect_failures = [check.hub_vpc_sc_enforced_when_prod_present]
}
