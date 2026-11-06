# Root-level contract test. Mocks the default aws provider (so no real
# credentials or role assumption happens) and overrides the aws-organization
# remote-state data source with a known cross-root contract. Asserts the keys
# the root consumes from remote state (organization_id, management_account_id,
# account_role_arns[shared_services]) are readable and that the org ARN the root
# builds for RAM sharing is well-formed.
#
# validate already covers syntax/type wiring; this guards the remote-state
# contract shape the root depends on.

mock_provider "aws" {}

variables {
  # Isolate the suite from any committed config/landing-zone.yaml.
  landing_zone_config_path = ""
  landing_zone_name        = "acme"
}

run "consumes_remote_state_contract" {
  command = plan

  override_data {
    target = data.terraform_remote_state.aws_organization
    values = {
      outputs = {
        organization_id       = "o-abcdefghij"
        management_account_id = "111111111111"
        account_ids           = { shared_services = "777777777777" }
        account_role_arns = {
          shared_services = "arn:aws:iam::222222222222:role/cross-account"
        }
      }
    }
  }

  assert {
    condition     = data.terraform_remote_state.aws_organization[0].outputs.organization_id == "o-abcdefghij"
    error_message = "remote-state organization_id contract key must be readable by the root"
  }

  assert {
    condition     = data.terraform_remote_state.aws_organization[0].outputs.account_role_arns["shared_services"] != ""
    error_message = "remote-state account_role_arns must expose the shared_services role the provider assumes"
  }

  assert {
    condition     = local.org_arn == "arn:aws:organizations::111111111111:organization/o-abcdefghij"
    error_message = "org_arn must be built from management_account_id and organization_id for RAM org-wide sharing"
  }
}

# landing_zone_name has no default and rejects the upstream placeholders.
run "rejects_placeholder_landing_zone_name" {
  command = plan

  variables {
    landing_zone_name = "ashes"
  }

  override_data {
    target = data.terraform_remote_state.aws_organization
    values = {
      outputs = {
        organization_id       = "o-abcdefghij"
        management_account_id = "111111111111"
        account_ids           = { shared_services = "777777777777" }
        account_role_arns = {
          shared_services = "arn:aws:iam::222222222222:role/cross-account"
        }
      }
    }
  }

  expect_failures = [var.landing_zone_name]
}

# Stage contract override (FAST-style): organization_contract replaces the
# aws-organization remote-state read entirely (no override_data here).
run "organization_contract_skips_remote_state" {
  command = plan

  variables {
    organization_contract = {
      organization_id       = "o-abcdefghij"
      management_account_id = "111111111111"
      account_ids           = { shared_services = "777777777777" }
    }
  }

  assert {
    condition     = length(data.terraform_remote_state.aws_organization) == 0 && local.org_arn == "arn:aws:organizations::111111111111:organization/o-abcdefghij"
    error_message = "a supplied organization_contract must skip the aws-organization read and feed the root"
  }
}
