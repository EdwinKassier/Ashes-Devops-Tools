# Cross-root contract for the aws-network root: how it sources the
# aws-organization contract (organization_id / management_account_id /
# account_ids) from the three places it can come from, in precedence order:
#   1. var.organization_contract
#   2. aws.contracts.organization in the landing-zone config file
#   3. the aws-organization workspace's remote state (overridden here)
# plus the other config-file fallbacks the root shares with aws-security
# (log_archive_bucket_name, aws.enabled_regions, org.profile).

mock_provider "aws" {}

variables {
  landing_zone_config_path = ""
  landing_zone_name        = "acme"
  log_archive_bucket_name  = "acme-org-log-archive"
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
      ou_ids                = { Infrastructure = "ou-abcd-infra00000" }
      account_ids           = { network = "666666666666", shared_services = "777777777777" }
      account_role_arns = {
        network = "arn:aws:iam::666666666666:role/cross-account"
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
    condition     = local.org.account_ids["network"] == "666666666666" && local.org_arn == "arn:aws:organizations::111111111111:organization/o-abcdefghij"
    error_message = "remote-state account_ids and the org ARN for RAM sharing must come from the remote state."
  }
}

run "config_without_contract_still_reads_remote_state" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-no-contract.yaml"
    log_archive_bucket_name  = null
  }

  assert {
    condition     = local.read_organization && local.org.organization_id == "o-abcdefghij" && local.tfc_organization == "cfg-tfc"
    error_message = "a config file with no aws.contracts.organization must not suppress the remote-state read."
  }

  assert {
    condition     = local.log_archive_bucket_name == "cfgco-org-log-archive"
    error_message = "log_archive_bucket_name must fall back to aws.log_archive_bucket_name (cross-root naming contract)."
  }
}

run "config_contract_replaces_remote_state" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.yaml"
    landing_zone_name        = null
    log_archive_bucket_name  = null
    availability_zones       = ["eu-west-1a", "eu-west-1b"]
    regional_cidrs           = { eu-west-1 = "10.0.0.0/12", eu-west-2 = "10.16.0.0/12" }
  }

  assert {
    condition     = !local.read_organization && length(data.terraform_remote_state.aws_organization) == 0
    error_message = "aws.contracts.organization in the config file must skip the aws-organization read."
  }

  assert {
    condition     = local.org.account_ids["network"] == "066666666666" && local.org_arn == "arn:aws:organizations::012345678901:organization/o-cfgcfgcfg0"
    error_message = "the config-file contract must feed local.org and the org ARN (quoted IDs keep their leading zero)."
  }

  assert {
    condition = (
      local.landing_zone_name == "cfgco" && local.aws_region == "eu-west-1" &&
      join(",", local.aws_enabled_regions) == "eu-west-1,eu-west-2" &&
      local.log_archive_bucket_name == "cfgco-org-log-archive"
    )
    error_message = "name / region / enabled regions / log-archive bucket must fall back to the config file."
  }

  # org.profile = starter in the fixture drops the Network Firewall.
  assert {
    condition     = local.profile == "starter" && local.enable_network_firewall == false
    error_message = "org.profile from the config file must drive the profile-dependent toggles."
  }
}

run "variable_contract_beats_config_contract" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone.yaml"
    profile                  = "production"
    aws_enabled_regions      = ["eu-west-2"]
    organization_contract = {
      organization_id       = "o-varsvarsva"
      management_account_id = "999999999999"
      account_ids           = { network = "888888888888" }
    }
  }

  assert {
    condition     = !local.read_organization && local.org_arn == "arn:aws:organizations::999999999999:organization/o-varsvarsva" && local.org.account_ids["network"] == "888888888888"
    error_message = "var.organization_contract must win over aws.contracts.organization."
  }

  assert {
    condition     = local.profile == "production" && local.enable_network_firewall == true && join(",", local.aws_enabled_regions) == "eu-west-2" && local.log_archive_bucket_name == "acme-org-log-archive"
    error_message = "explicit variables must win over the config file."
  }
}
