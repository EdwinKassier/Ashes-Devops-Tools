# Root-level contract test. Mocks the default aws provider (so no real
# credentials or role assumption happens) and overrides the aws-organization
# remote-state data source with a known cross-root contract. Asserts the keys
# the root consumes from remote state (organization_id, management_account_id,
# account_role_arns[network]) are readable and that the org ARN the root builds
# for RAM sharing is well-formed.
#
# validate already covers syntax/type wiring; this guards the remote-state
# contract shape the root depends on.

mock_provider "aws" {}

variables {
  log_archive_bucket_name = "ashes-org-log-archive"
}

run "consumes_remote_state_contract" {
  command = plan

  override_data {
    target = data.terraform_remote_state.aws_organization
    values = {
      outputs = {
        organization_id       = "o-abcdefghij"
        management_account_id = "111111111111"
        account_role_arns = {
          network = "arn:aws:iam::666666666666:role/cross-account"
        }
      }
    }
  }

  assert {
    condition     = data.terraform_remote_state.aws_organization.outputs.organization_id == "o-abcdefghij"
    error_message = "remote-state organization_id contract key must be readable by the root"
  }

  assert {
    condition     = data.terraform_remote_state.aws_organization.outputs.account_role_arns["network"] != ""
    error_message = "remote-state account_role_arns must expose the network role the provider assumes"
  }

  assert {
    condition     = local.org_arn == "arn:aws:organizations::111111111111:organization/o-abcdefghij"
    error_message = "org_arn must be built from management_account_id and organization_id for RAM org-wide sharing"
  }
}
