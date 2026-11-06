# Cross-root contract for the aws-shared-services root: how it sources the
# aws-organization contract (organization_id / management_account_id /
# account_ids) from the three places it can come from, in precedence order:
#   1. var.organization_contract
#   2. aws.contracts.organization in the landing-zone config file
#   3. the aws-organization workspace's remote state (overridden here)
# and that the org ARN it builds for RAM org-wide sharing follows the source.

mock_provider "aws" {}

variables {
  landing_zone_config_path = ""
  landing_zone_name        = "acme"
}

# Remote state carries more outputs than this root consumes; the root must
# project only the three contract fields it needs.
override_data {
  target = data.terraform_remote_state.aws_organization
  values = {
    outputs = {
      organization_id       = "o-abcdefghij"
      organization_root_id  = "r-abcd"
      management_account_id = "111111111111"
      ou_ids                = { Workloads = "ou-abcd-workloads0" }
      account_ids           = { shared_services = "777777777777", network = "666666666666" }
      account_role_arns = {
        shared_services = "arn:aws:iam::777777777777:role/cross-account"
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
    condition     = toset(keys(local.org)) == toset(["organization_id", "management_account_id", "account_ids"])
    error_message = "local.org must project the remote state onto exactly organization_id / management_account_id / account_ids."
  }

  assert {
    condition     = local.org.account_ids["shared_services"] == "777777777777" && local.org_arn == "arn:aws:organizations::111111111111:organization/o-abcdefghij"
    error_message = "remote-state account_ids and the org ARN for RAM sharing must come from the remote state."
  }

  # Both cost toggles default off: nothing shared-services-billed is planned.
  assert {
    condition     = output.ca_arn == null && length(output.secret_arns) == 0
    error_message = "with enable_private_ca / enable_secrets_baseline off, ca_arn must be null and secret_arns empty."
  }
}

run "config_without_contract_still_reads_remote_state" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-no-contract.yaml"
  }

  assert {
    condition     = local.read_organization && local.org.organization_id == "o-abcdefghij" && local.tfc_organization == "cfg-tfc"
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
    condition     = local.org.account_ids["shared_services"] == "077777777777" && local.org_arn == "arn:aws:organizations::012345678901:organization/o-cfgcfgcfg0"
    error_message = "the config-file contract must feed local.org and the org ARN (quoted IDs keep their leading zero)."
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
      organization_id       = "o-varsvarsva"
      management_account_id = "999999999999"
      account_ids           = { shared_services = "888888888888" }
    }
  }

  assert {
    condition     = !local.read_organization && local.org_arn == "arn:aws:organizations::999999999999:organization/o-varsvarsva" && local.org.account_ids["shared_services"] == "888888888888"
    error_message = "var.organization_contract must win over aws.contracts.organization."
  }
}
