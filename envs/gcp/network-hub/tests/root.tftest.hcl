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
