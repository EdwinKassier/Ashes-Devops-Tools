# Cross-root OUTPUT CONTRACT test for the gcp-projects root.
#
# gcp-network-hub reads project_ids/project_numbers, and gcp-workload reads
# environment_config, from this root. environment_config combines the org folders
# and tag values (upstream remote state) with this root's project IDs/numbers.
# This test overrides both upstream remote states and the projects stage with a
# known contract and asserts the root composes and re-exports it correctly.

mock_provider "google" {}
mock_provider "google-beta" {}
mock_provider "random" {}

variables {
  project_prefix = "acme"
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
  target = data.terraform_remote_state.gcp_bootstrap
  values = {
    outputs = {
      admin_project_id = "acme-admin-abcd"
      suffix           = "abcd"
    }
  }
}

override_data {
  target = data.terraform_remote_state.gcp_organization
  values = {
    outputs = {
      billing_account = "billingAccounts/000000-111111-222222"
      folders = {
        dev = { id = "folders/111", display_name = "Development" }
      }
      tag_values = {
        "environment-dev" = "tagValues/123"
      }
    }
  }
}

override_module {
  target = module.projects
  outputs = {
    projects = {}
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

run "projects_output_contract" {
  command = plan

  assert {
    condition     = contains(keys(output.project_ids), "shared-hub") && contains(keys(output.project_ids), "shared-dns") && contains(keys(output.project_ids), "dev-host")
    error_message = "project_ids must expose the shared hub/dns and per-environment host projects (consumed by gcp-network-hub)."
  }

  # Bind producer to consumer (audit M-iac): assert the FULL key set gcp-workload
  # consumes from environment_config, so a rename or drop of any key fails HERE,
  # at the producer. The consumer's own test mocks this shape and cannot catch
  # producer drift, so this is the real guard on the seam.
  assert {
    condition = alltrue([
      for k in ["folder_id", "folder_name", "host_project_id", "host_project_number", "region", "cidr_block", "labels", "tag_value_ids"] :
      contains(keys(output.environment_config["dev"]), k)
    ])
    error_message = "environment_config must expose every key gcp-workload consumes: folder_id, folder_name, host_project_id, host_project_number, region, cidr_block, labels, tag_value_ids."
  }

  assert {
    condition     = output.environment_config["dev"].host_project_id == "acme-dev-host-abcd" && output.environment_config["dev"].host_project_number == "333333333333" && output.environment_config["dev"].folder_name == "Development" && output.environment_config["dev"].tag_value_ids.environment == "tagValues/123"
    error_message = "environment_config must combine org folders/tag values with this root's project IDs/numbers (consumed by gcp-workload)."
  }
}
