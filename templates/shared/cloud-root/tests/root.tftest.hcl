# Root-convention suite for the provider-agnostic root scaffold. Plans with no
# credentials; keep it when cloning to envs/<cloud>/<layer>/ and add one
# `mock_provider "<your-cloud>" {}` per provider declared in versions.tf
# (this scaffold declares none, so there is nothing to mock yet):
#
# mock_provider "azurerm" {}

variables {
  # Isolate from the repo's config/landing-zone.yaml (see CLAUDE.md: Configuration).
  landing_zone_config_path = ""
}

# A supplied contract replaces the upstream read entirely (no override_data).
run "contract_skips_remote_state" {
  command = plan

  variables {
    organization_contract = { tenant_id = "contract-tenant" }
  }

  assert {
    condition     = length(data.terraform_remote_state.cloud_organization) == 0
    error_message = "a supplied organization_contract must skip the remote-state read"
  }

  assert {
    condition     = output.upstream_contract.tenant_id == "contract-tenant"
    error_message = "contract values must flow into local.upstream"
  }
}

# No contract: the root reads the upstream workspace (mocked here).
run "remote_state_read_without_contract" {
  command = plan

  variables {
    tfc_organization = "acme-tfc"
  }

  override_data {
    target = data.terraform_remote_state.cloud_organization[0]
    values = {
      outputs = { contract = { tenant_id = "state-tenant" } }
    }
  }

  assert {
    condition     = length(data.terraform_remote_state.cloud_organization) == 1 && output.upstream_contract.tenant_id == "state-tenant"
    error_message = "without a contract the root must read the upstream workspace and re-export its contract"
  }
}

run "tfc_organization_required_for_remote_state" {
  command = plan

  expect_failures = [var.tfc_organization]
}

# Config-file fallback: the TFC org and the contract both come from the file.
run "config_file_fallback" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.yaml"
  }

  assert {
    condition = (
      local.tfc_organization == "fixture-tfc-org" &&
      length(data.terraform_remote_state.cloud_organization) == 0 &&
      output.upstream_contract.tenant_id == "fixture-tenant"
    )
    error_message = "org.tfc.organization and <cloud>.contracts.organization must come from the config file"
  }
}
