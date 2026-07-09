# Root-level contract test. Mocks the default aws provider (so no real
# credentials or role assumption happens), mocks the module's Identity Center
# instances data source so local.instance_arn resolves, and overrides the
# aws-organization remote-state data source with a known cross-root contract.
# Asserts the keys the root consumes from remote state (account_role_arns for
# the provider, account_ids for wiring assignments) are readable.
#
# validate already covers syntax/type wiring; this guards the remote-state
# contract shape the root depends on.

mock_provider "aws" {
  mock_data "aws_ssoadmin_instances" {
    defaults = {
      arns               = ["arn:aws:sso:::instance/ssoins-0000000000000000"]
      identity_store_ids = ["d-0000000000"]
    }
  }
}

run "consumes_remote_state_contract" {
  command = plan

  override_data {
    target = data.terraform_remote_state.aws_organization
    values = {
      outputs = {
        organization_id       = "o-abcdefghij"
        management_account_id = "111111111111"
        account_ids = {
          shared_services = "222222222222"
          network         = "333333333333"
        }
        account_role_arns = {
          shared_services = "arn:aws:iam::222222222222:role/cross-account"
          network         = "arn:aws:iam::333333333333:role/cross-account"
        }
      }
    }
  }

  assert {
    condition     = data.terraform_remote_state.aws_organization.outputs.account_role_arns["shared_services"] != ""
    error_message = "remote-state account_role_arns must expose the shared_services role the provider assumes"
  }

  assert {
    condition     = local.account_ids["shared_services"] == "222222222222"
    error_message = "remote-state account_ids must expose member-account IDs for wiring assignments"
  }
}
