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
  # Isolate the suite from any committed config/landing-zone.yaml.
  landing_zone_config_path = ""
  project_prefix           = "acme"
  environments = {
    dev = {
      display_name            = "Development"
      region                  = "europe-west1"
      cidr_block              = "10.10.0.0/16"
      budget_monthly_limit    = 100
      iam_group_role_bindings = {}
      is_production           = true
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
      scoped_access_policy_ids = {
        dev = "555555555"
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
      for k in ["folder_id", "folder_name", "host_project_id", "host_project_number", "region", "cidr_block", "labels", "tag_value_ids", "is_production", "vpc_sc_access_policy_id"] :
      contains(keys(output.environment_config["dev"]), k)
    ])
    error_message = "environment_config must expose every key gcp-workload consumes: folder_id, folder_name, host_project_id, host_project_number, region, cidr_block, labels, tag_value_ids, is_production, vpc_sc_access_policy_id."
  }

  assert {
    condition     = output.environment_config["dev"].host_project_id == "acme-dev-host-abcd" && output.environment_config["dev"].host_project_number == "333333333333" && output.environment_config["dev"].folder_name == "Development" && output.environment_config["dev"].tag_value_ids.environment == "tagValues/123"
    error_message = "environment_config must combine org folders/tag values with this root's project IDs/numbers (consumed by gcp-workload)."
  }
}

# The explicit production marker and the env's scoped access policy reach
# gcp-workload through environment_config (no name-based prod detection).
run "environment_config_carries_production_and_scoped_policy" {
  command = plan

  assert {
    condition     = output.environment_config["dev"].is_production == true && output.environment_config["dev"].vpc_sc_access_policy_id == "555555555"
    error_message = "environment_config must surface is_production and the environment's scoped access policy ID."
  }
}

run "environment_config_tolerates_pre_scoped_org_state" {
  command = plan

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

  assert {
    condition     = output.environment_config["dev"].vpc_sc_access_policy_id == null
    error_message = "an org state without scoped_access_policy_ids must yield a null policy ID, not an error."
  }
}

# Stage contract override (FAST-style): bootstrap_contract / organization_contract
# replace the upstream remote-state reads entirely (count = 0).
run "contracts_skip_remote_state" {
  command = plan

  variables {
    bootstrap_contract = {
      admin_project_id = "acme-admin-abcd"
      suffix           = "abcd"
    }
    organization_contract = {
      billing_account = "billingAccounts/000000-111111-222222"
      folders         = { dev = { id = "folders/999", name = "folders/999", display_name = "Development" } }
      tag_values      = { "environment-dev" = "tagValues/999" }
    }
  }

  assert {
    condition = (
      length(data.terraform_remote_state.gcp_bootstrap) == 0 &&
      length(data.terraform_remote_state.gcp_organization) == 0 &&
      output.environment_config["dev"].folder_id == "folders/999" &&
      output.environment_config["dev"].tag_value_ids.environment == "tagValues/999" &&
      output.environment_config["dev"].vpc_sc_access_policy_id == null
    )
    error_message = "supplied contracts must skip the gcp-bootstrap / gcp-organization reads and feed environment_config"
  }
}
