# Cross-root contract for the aws-identity root: how it sources the
# aws-organization contract (account_ids) from the three places it can come
# from, in precedence order:
#   1. var.organization_contract
#   2. aws.contracts.organization in the landing-zone config file
#   3. the aws-organization workspace's remote state (overridden here)
# and that the contract surfaces through the account_ids output operators use
# to wire assignments.

mock_provider "aws" {
  mock_data "aws_ssoadmin_instances" {
    defaults = {
      arns               = ["arn:aws:sso:::instance/ssoins-0000000000000000"]
      identity_store_ids = ["d-0000000000"]
    }
  }
}

variables {
  landing_zone_config_path = ""
  landing_zone_name        = "acme"
}

# Remote state carries more outputs than this root consumes; the root must
# project only account_ids.
override_data {
  target = data.terraform_remote_state.aws_organization
  values = {
    outputs = {
      contract = {
        organization_id       = "o-abcdefghij"
        management_account_id = "111111111111"
        ou_ids                = { Workloads = "ou-abcd-workloads0" }
        account_ids = {
          shared_services = "222222222222"
          network         = "333333333333"
        }
        account_role_arns = {
          shared_services = "arn:aws:iam::222222222222:role/cross-account"
        }
      }
    }
  }
}

run "remote_state_is_projected_onto_the_contract" {
  command = plan

  assert {
    condition     = local.read_organization && length(data.terraform_remote_state.aws_organization) == 1
    error_message = "with no organization_contract anywhere the aws-organization remote state must be read."
  }

  assert {
    condition     = toset(keys(local.org)) == toset(["organization_id", "organization_root_id", "management_account_id", "ou_ids", "account_ids", "account_role_arns"])
    error_message = "local.org must project the remote contract onto the shared aws organization_contract type (all six fields)."
  }

  assert {
    condition     = output.account_ids == tomap({ shared_services = "222222222222", network = "333333333333" })
    error_message = "the account_ids output must echo the remote-state account_ids map unchanged."
  }

  assert {
    condition     = output.identity_center_instance_arn == "arn:aws:sso:::instance/ssoins-0000000000000000"
    error_message = "the discovered Identity Center instance ARN must be surfaced."
  }
}

# Assignments wired with an account ID taken from the contract plan cleanly.
run "assignment_targets_contract_account" {
  command = plan

  variables {
    assignments = {
      readonly-network = {
        permission_set = "ReadOnly"
        principal_type = "GROUP"
        principal_id   = "9067d0e5d1-11111111-2222-3333-4444-555555555555"
        account_id     = "333333333333"
      }
    }
  }

  assert {
    condition     = local.assignments["readonly-network"].account_id == output.account_ids["network"]
    error_message = "an assignment pointed at a contract account ID must pass through unchanged."
  }
}

run "config_without_contract_still_reads_remote_state" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-no-contract.yaml"
  }

  assert {
    condition     = local.read_organization && output.account_ids["shared_services"] == "222222222222" && local.tfc_organization == "cfg-tfc"
    error_message = "a config file with no aws.contracts.organization must not suppress the remote-state read."
  }
}

run "config_contract_replaces_remote_state" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.yaml"
    landing_zone_name        = null
  }

  assert {
    condition     = !local.read_organization && length(data.terraform_remote_state.aws_organization) == 0
    error_message = "aws.contracts.organization in the config file must skip the aws-organization read."
  }

  assert {
    condition     = output.account_ids["shared_services"] == "022222222222" && output.account_ids["network"] == "033333333333"
    error_message = "the config-file contract must feed account_ids (quoted IDs keep their leading zero)."
  }

  assert {
    condition     = local.landing_zone_name == "cfgco" && local.aws_region == "eu-west-1" && local.cost_center == "cc-1234" && local.owner == "cfg-platform"
    error_message = "unset scalars must fall back to org.name / org.regions.aws / org.cost_center / org.owner."
  }
}

run "variable_contract_beats_config_contract" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.yaml"
    organization_contract = {
      account_ids = { shared_services = "444444444444" }
    }
  }

  assert {
    condition     = !local.read_organization && output.account_ids == tomap({ shared_services = "444444444444" })
    error_message = "var.organization_contract must win over aws.contracts.organization."
  }
}
