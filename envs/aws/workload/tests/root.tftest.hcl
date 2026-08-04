# Root-level contract test. Mocks BOTH aws providers (default + us_east_1 alias)
# so no real credentials or role assumption happens, and overrides BOTH upstream
# remote-state data sources with a known cross-root contract. Asserts the keys
# this root consumes — account_role_arns[workload_account_key] (both providers),
# tgw_id and ipam_pool_ids[aws_region] (aws_network) — are readable.
#
# validate already covers syntax/type wiring; this guards the remote-state
# contract shape the root depends on.

mock_provider "aws" {}
mock_provider "aws" { alias = "us_east_1" }

variables {
  workload_account_key    = "workload_dev"
  log_archive_bucket_name = "ashes-org-log-archive"
  config_role_arn         = "arn:aws:iam::222222222222:role/config-recorder"
  kms_key_arn             = "arn:aws:kms:eu-west-2:222222222222:key/abcd-1234"
}

run "consumes_remote_state_contracts" {
  command = plan

  override_data {
    target = data.terraform_remote_state.aws_organization
    values = {
      outputs = {
        account_role_arns = {
          workload_dev = "arn:aws:iam::222222222222:role/cross-account"
        }
      }
    }
  }

  override_data {
    target = data.terraform_remote_state.aws_network
    values = {
      outputs = {
        tgw_id        = "tgw-000000000000abcd"
        ipam_pool_ids = { "eu-west-2" = "ipam-pool-eu-west-2-0" }
      }
    }
  }

  # The workload-account role the providers assume is readable from the org contract.
  assert {
    condition     = data.terraform_remote_state.aws_organization.outputs.account_role_arns[var.workload_account_key] != ""
    error_message = "aws_organization account_role_arns must expose the workload_account_key role"
  }

  # The shared TGW id is readable from the network contract.
  assert {
    condition     = data.terraform_remote_state.aws_network.outputs.tgw_id == "tgw-000000000000abcd"
    error_message = "aws_network tgw_id contract key must be readable by the root"
  }

  # The regional IPAM pool for this root's region is readable from the network contract.
  assert {
    condition     = data.terraform_remote_state.aws_network.outputs.ipam_pool_ids[var.aws_region] == "ipam-pool-eu-west-2-0"
    error_message = "aws_network ipam_pool_ids must expose a pool for var.aws_region"
  }
}
