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
  default_tags            = { CostCenter = "networking" }
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

  # Provider default_tags carry the canonical cost-allocation keys.
  assert {
    condition = (
      local.aws_default_tags["Workspace"] == "aws-network" &&
      local.aws_default_tags["ManagedBy"] == "terraform" &&
      alltrue([for k in ["CostCenter", "Environment", "Owner", "LandingZone"] : contains(keys(local.aws_default_tags), k)])
    )
    error_message = "aws provider default_tags must carry the canonical tag set"
  }

  # A default_tags override wins over the canonical value.
  assert {
    condition     = local.aws_default_tags["CostCenter"] == "networking"
    error_message = "var.default_tags must be merged last so it can override canonical tags"
  }

  assert {
    condition     = local.org_arn == "arn:aws:organizations::111111111111:organization/o-abcdefghij"
    error_message = "org_arn must be built from management_account_id and organization_id for RAM org-wide sharing"
  }
}
