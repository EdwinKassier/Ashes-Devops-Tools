# Hub side of the environment peerings. gcp-network-hub peers the hub VPC with
# every peering-mode environment whose spoke network already exists (GCP
# rejects a peering to a missing network), one uniquely named peering per
# environment. The network-hub stage is planned for real down to its peering
# resource; only its two network compositions are stubbed.

mock_provider "google" {}
mock_provider "google-beta" {}
mock_provider "random" {}

variables {
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
    qa = {
      display_name            = "QA"
      region                  = "europe-west1"
      cidr_block              = "10.11.0.0/16"
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
          shared = { id = "folders/100", name = "folders/100", display_name = "Shared" }
          dev    = { id = "folders/111", name = "folders/111", display_name = "Development" }
          qa     = { id = "folders/112", name = "folders/112", display_name = "QA" }
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
          "qa-host"    = "acme-qa-host-abcd"
        }
        project_numbers = {
          "shared-hub" = "111111111111"
          "shared-dns" = "222222222222"
          "dev-host"   = "333333333333"
          "qa-host"    = "444444444444"
        }
      }
    }
  }
}

# dev's spoke network exists (its workload has applied); qa's does not yet.
override_data {
  target = data.google_compute_networks.spoke["dev"]
  values = {
    networks = ["default", "acme-dev-vpc"]
  }
}

override_data {
  target = data.google_compute_networks.spoke["qa"]
  values = {
    networks = []
  }
}

override_module {
  target = module.network_hub.module.hub
  outputs = {
    network_self_link = "projects/acme-hub-abcd/global/networks/acme-hub-vpc"
    network_name      = "acme-hub-vpc"
    subnets           = { public = {}, private = {}, database = {} }
    nat_ip            = null
  }
}

override_module {
  target = module.network_hub.module.dns_anchor
  outputs = {
    network_self_link = "projects/acme-dns-abcd/global/networks/acme-dns-vpc"
    dns_zone_names    = { "internal-root" = "internal-root" }
    dns_names         = { "internal-root" = "internal.local." }
  }
}

run "peers_existing_spokes_only" {
  command = plan

  assert {
    condition     = toset(keys(data.google_compute_networks.spoke)) == toset(["dev", "qa"])
    error_message = "every peering-mode environment with a host project is a candidate."
  }

  assert {
    condition     = toset(keys(output.spoke_peering_states)) == toset(["dev"])
    error_message = "only environments whose spoke network exists get a hub-side peering (qa has no network yet)."
  }
}

run "spoke_peerings_can_be_turned_off" {
  command = plan

  variables {
    create_spoke_peerings = false
  }

  assert {
    condition     = length(data.google_compute_networks.spoke) == 0 && length(output.spoke_peering_states) == 0
    error_message = "create_spoke_peerings = false lists no spoke networks and creates no hub-side peering."
  }
}
