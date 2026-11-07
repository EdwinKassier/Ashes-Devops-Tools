# Stage contract overrides (FAST-style): a supplied <layer>_contract (variable or
# aws.contracts.<layer> in config/landing-zone.yaml) replaces the upstream
# terraform_remote_state read entirely. NO override_data here — every run proves
# the root plans without the upstream workspaces (length(data...) == 0).

mock_provider "aws" {}
mock_provider "aws" { alias = "us_east_1" }

variables {
  landing_zone_config_path = ""
  landing_zone_name        = "acme"
  workload_account_key     = "workload_dev"
  kms_key_arn              = "arn:aws:kms:eu-west-2:222222222222:key/abcd-1234"

  organization_contract = { account_ids = { workload_dev = "222222222222" } }
  security_contract     = { log_archive_bucket_name = "acme-org-log-archive" }
}

run "contracts_replace_remote_state" {
  command = plan

  variables {
    network_contract = {
      tgw_id        = "tgw-00000000contract"
      ipam_pool_ids = { "eu-west-2" = "ipam-pool-contract" }
    }
  }

  assert {
    condition = (
      length(data.terraform_remote_state.aws_organization) == 0 &&
      length(data.terraform_remote_state.aws_network) == 0 &&
      length(data.terraform_remote_state.aws_security) == 0
    )
    error_message = "a supplied contract must skip the matching remote-state read"
  }

  assert {
    condition = (
      local.workload_account_id == "222222222222" &&
      local.ipam_pool_id == "ipam-pool-contract" &&
      local.log_archive_bucket_name == "acme-org-log-archive" &&
      module.aws_workload.tgw_routes["private"][0].transit_gateway_id == "tgw-00000000contract"
    )
    error_message = "contract values must flow into the providers' guard, the spoke and the log destinations"
  }
}

# aws-workload without aws-network: a standalone VPC (no TGW, no IPAM, no
# routes off the VPC) — the network layer is genuinely optional.
run "standalone_without_network_hub" {
  command = plan

  variables {
    enable_network_hub = false
  }

  assert {
    condition     = length(data.terraform_remote_state.aws_network) == 0 && local.tgw_id == null && local.ipam_pool_id == ""
    error_message = "enable_network_hub = false must not read aws-network and must pass no TGW / IPAM pool"
  }

  assert {
    condition     = length(module.aws_workload.tgw_routes) == 0 && module.aws_workload.tgw_attachment_id == null
    error_message = "standalone mode must plan no TGW attachment and no TGW routes"
  }
}

# Without a contract the root still reads the upstream workspace (count = 1).
run "remote_state_read_without_contract" {
  command = plan

  variables {
    security_contract = null
  }

  override_data {
    target = data.terraform_remote_state.aws_network
    values = { outputs = { tgw_id = "tgw-000000000000abcd", ipam_pool_ids = { "eu-west-2" = "ipam-pool-eu-west-2-0" } } }
  }
  override_data {
    target = data.terraform_remote_state.aws_security
    values = { outputs = { log_archive_bucket_name = "remote-org-log-archive" } }
  }

  assert {
    condition     = length(data.terraform_remote_state.aws_security) == 1 && local.log_archive_bucket_name == "remote-org-log-archive"
    error_message = "with no security contract the bucket name must come from the aws-security remote state"
  }
}

# The same contracts from config/landing-zone.yaml (aws.contracts.<layer>).
run "contracts_from_config_file" {
  command = plan

  variables {
    landing_zone_config_path = "tests/fixtures/landing-zone-contracts.yaml"
    landing_zone_name        = null
    workload_account_key     = null
    environment              = "dev"
    organization_contract    = null
    security_contract        = null
  }

  assert {
    condition = (
      length(data.terraform_remote_state.aws_organization) == 0 &&
      length(data.terraform_remote_state.aws_network) == 0 &&
      length(data.terraform_remote_state.aws_security) == 0 &&
      local.workload_account_id == "222222222222" &&
      local.tgw_id == "tgw-0000000000000cfg" &&
      local.ipam_pool_id == "ipam-pool-cfg" &&
      local.log_archive_bucket_name == "cfgco-org-log-archive"
    )
    error_message = "aws.contracts.<layer> in the config file must replace the remote-state reads"
  }
}

run "rejects_malformed_network_contract" {
  command = plan

  variables {
    network_contract = { tgw_id = "not-a-tgw" }
  }

  expect_failures = [var.network_contract]
}
