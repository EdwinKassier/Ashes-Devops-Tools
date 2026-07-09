# Root-level contract test. Mocks all five aws providers (so no real credentials
# or role assumption happens) and overrides the aws-organization remote-state
# data source with a known cross-root contract. Asserts the root plans and that
# the keys the root consumes from remote state flow into the stage inputs.
#
# validate already covers syntax/type wiring; this guards the remote-state
# contract shape (organization_id / organization_root_id / management_account_id
# / account_ids[*] / account_role_arns[*]) the root depends on.

mock_provider "aws" {}
mock_provider "aws" { alias = "security_tooling" }
mock_provider "aws" { alias = "log_archive" }
mock_provider "aws" { alias = "forensics" }

variables {
  log_archive_bucket_name = "ashes-org-log-archive"
  key_admin_arn           = "arn:aws:iam::111111111111:role/key-admin"
  config_role_arn         = "arn:aws:iam::222222222222:role/aws-config-recorder"
  aggregator_role_arn     = "arn:aws:iam::222222222222:role/aws-config-aggregator"
  # Security Lake off so meta_store_manager_role_arn is not required.
  enable_security_lake = false
}

run "consumes_remote_state_contract" {
  command = plan

  override_data {
    target = data.terraform_remote_state.aws_organization
    values = {
      outputs = {
        organization_id       = "o-abcdefghij"
        organization_root_id  = "r-abcd"
        management_account_id = "111111111111"
        account_ids = {
          security_tooling = "222222222222"
          log_archive      = "333333333333"
          shared_services  = "444444444444"
          forensics        = "555555555555"
        }
        account_role_arns = {
          security_tooling = "arn:aws:iam::222222222222:role/cross-account"
          log_archive      = "arn:aws:iam::333333333333:role/cross-account"
          forensics        = "arn:aws:iam::555555555555:role/cross-account"
        }
      }
    }
  }

  assert {
    condition     = data.terraform_remote_state.aws_organization.outputs.organization_root_id == "r-abcd"
    error_message = "remote-state organization_root_id contract key must be readable by the root"
  }

  assert {
    condition     = data.terraform_remote_state.aws_organization.outputs.account_ids["forensics"] == "555555555555"
    error_message = "remote-state account_ids must expose the forensics account the root consumes"
  }

  assert {
    condition     = data.terraform_remote_state.aws_organization.outputs.account_role_arns["security_tooling"] != ""
    error_message = "remote-state account_role_arns must expose the security_tooling role the provider assumes"
  }
}
