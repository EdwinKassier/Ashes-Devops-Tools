# Root-convention suite for the AWS root scaffold. Runs with mock_provider and
# no credentials; keep it (renamed for the layer) when cloning to envs/aws/<layer>/.

mock_provider "aws" {}

variables {
  # Isolate from the repo's config/landing-zone.yaml (see CLAUDE.md: Configuration).
  landing_zone_config_path = ""
}

# A supplied contract replaces the upstream read entirely: no override_data, so
# this proves the root plans without the aws-organization workspace.
run "contract_skips_remote_state" {
  command = plan

  variables {
    organization_contract = { account_ids = { workload = "111111111111" } }
  }

  assert {
    condition     = length(data.terraform_remote_state.aws_organization) == 0
    error_message = "a supplied organization_contract must skip the aws-organization remote-state read"
  }

  assert {
    condition     = output.account_ids["workload"] == "111111111111"
    error_message = "contract account IDs must flow into the root's resolved account_ids"
  }
}

# No contract: the root reads aws-organization remote state (mocked here) and
# re-exports its account_ids contract.
run "remote_state_read_without_contract" {
  command = plan

  variables {
    tfc_organization = "acme-tfc"
  }

  override_data {
    target = data.terraform_remote_state.aws_organization[0]
    values = {
      outputs = { account_ids = { workload = "222222222222" } }
    }
  }

  assert {
    condition     = length(data.terraform_remote_state.aws_organization) == 1
    error_message = "without a contract the root must read the aws-organization workspace"
  }

  assert {
    condition     = output.account_ids["workload"] == "222222222222"
    error_message = "remote-state account IDs must flow into the root's resolved account_ids"
  }

  assert {
    condition     = output.aws_region == "eu-west-2" && tolist(local.aws_enabled_regions) == tolist(["eu-west-2"])
    error_message = "with no variable and no config file, the region must fall back to eu-west-2"
  }
}

# A remote-state read with no TFC organization anywhere fails the plan, and the
# error names the config key.
run "tfc_organization_required_for_remote_state" {
  command = plan

  expect_failures = [var.tfc_organization]
}

run "invalid_region_rejected" {
  command = plan

  variables {
    aws_region            = "eu-west"
    organization_contract = { account_ids = { workload = "111111111111" } }
  }

  expect_failures = [var.aws_region]
}

run "invalid_contract_account_id_rejected" {
  command = plan

  variables {
    organization_contract = { account_ids = { workload = "1234" } }
  }

  expect_failures = [var.organization_contract]
}

# Config-file fallback: with no variables set, every value comes from the file —
# including the contract, so no remote-state read happens.
run "config_file_fallback" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.yaml"
  }

  assert {
    condition = (
      output.aws_region == "us-east-1" &&
      tolist(local.aws_enabled_regions) == tolist(["us-east-1", "us-west-2"]) &&
      local.tfc_organization == "fixture-tfc-org"
    )
    error_message = "region, enabled regions and TFC org must come from the config file"
  }

  assert {
    condition     = length(data.terraform_remote_state.aws_organization) == 0 && output.account_ids["workload"] == "333333333333"
    error_message = "aws.contracts.organization in the config file must replace the remote-state read"
  }
}

# Explicit variables win over the config file.
run "variable_overrides_config_file" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.yaml"
    aws_region               = "eu-central-1"
  }

  assert {
    condition     = output.aws_region == "eu-central-1"
    error_message = "an explicit aws_region must override org.regions.aws"
  }
}
