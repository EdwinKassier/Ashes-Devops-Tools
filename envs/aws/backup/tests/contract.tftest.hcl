# Cross-root contract for the aws-backup root: how it sources the
# aws-organization contract (account_ids / account_role_arns / ou_ids) from the
# three places it can come from, in precedence order:
#   1. var.organization_contract
#   2. aws.contracts.organization in the landing-zone config file
#   3. the aws-organization workspace's remote state (overridden here)

mock_provider "aws" {}
mock_provider "aws" { alias = "backup" }

variables {
  landing_zone_config_path = ""
  landing_zone_name        = "acme"
  management_account_id    = "111111111111"
}

# Remote state carries more outputs than this root consumes; the root must
# project only the three contract fields it needs.
override_data {
  target = data.terraform_remote_state.aws_organization
  values = {
    outputs = {
      contract = {
        organization_id       = "o-abcdefghij"
        organization_root_id  = "r-abcd"
        management_account_id = "111111111111"
        ou_ids                = { Workloads = "ou-abcd-workloads0", Security = "ou-abcd-security00" }
        account_ids           = { backup = "444444444444", network = "666666666666" }
        account_role_arns = {
          backup  = "arn:aws:iam::444444444444:role/cross-account"
          network = "arn:aws:iam::666666666666:role/cross-account"
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
    condition = (
      local.org.ou_ids["Workloads"] == "ou-abcd-workloads0" &&
      local.org.account_ids["backup"] == "444444444444" &&
      local.org.account_role_arns["backup"] == "arn:aws:iam::444444444444:role/cross-account"
    )
    error_message = "the Workloads OU, backup account ID and backup role ARN must flow from remote state into local.org."
  }
}

# A config file without aws.contracts.organization still falls back to the read.
run "config_without_contract_still_reads_remote_state" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-no-contract.yaml"
    management_account_id    = null
  }

  assert {
    condition     = local.read_organization && local.org.ou_ids["Workloads"] == "ou-abcd-workloads0"
    error_message = "a config file with no aws.contracts.organization must not suppress the remote-state read."
  }

  assert {
    condition     = local.tfc_organization == "cfg-tfc" && local.management_account_id == "012345678901"
    error_message = "tfc_organization / management_account_id must come from the config file (leading zero kept)."
  }
}

run "config_contract_replaces_remote_state" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.yaml"
    landing_zone_name        = null
    management_account_id    = null
  }

  assert {
    condition     = !local.read_organization && length(data.terraform_remote_state.aws_organization) == 0
    error_message = "aws.contracts.organization in the config file must skip the aws-organization read."
  }

  assert {
    condition = (
      local.org.ou_ids["Workloads"] == "ou-cfgo-workloads0" &&
      local.org.account_ids["backup"] == "044444444444" &&
      local.org.account_role_arns["backup"] == "arn:aws:iam::044444444444:role/cross-account"
    )
    error_message = "the config-file contract must feed local.org (quoted account IDs keep their leading zero)."
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
      account_ids       = { backup = "555555555555" }
      account_role_arns = { backup = "arn:aws:iam::555555555555:role/cross-account" }
      ou_ids            = { Workloads = "ou-vars-workloads0" }
    }
  }

  assert {
    condition     = !local.read_organization && local.org.ou_ids["Workloads"] == "ou-vars-workloads0" && local.org.account_ids["backup"] == "555555555555"
    error_message = "var.organization_contract must win over aws.contracts.organization."
  }

  assert {
    condition     = local.management_account_id == "111111111111" && local.landing_zone_name == "acme"
    error_message = "explicit variables must win over the config file."
  }
}
