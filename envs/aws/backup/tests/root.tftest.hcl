# Root-level contract test. Mocks both aws providers (so no real credentials or
# role assumption happens) and overrides the aws-organization remote-state data
# source with a known cross-root contract. Asserts the root plans and that the
# keys the root consumes from remote state (account_role_arns["backup"] for the
# provider assume_role, ou_ids["Workloads"] for the org policy attachment) flow
# into the plan.
#
# validate already covers syntax/type wiring; this guards the remote-state
# contract shape the root depends on.

mock_provider "aws" {}
mock_provider "aws" { alias = "backup" }

variables {
  # Isolate the suite from any committed config/landing-zone.yaml.
  landing_zone_config_path = ""
  landing_zone_name        = "acme"
  management_account_id    = "111111111111" # C4 account guard
  # backup_role_arn / restore_testing_role_arn omitted: the stage creates both
  # roles (member-account StackSet role, backup-account restore-testing role).
}

run "consumes_remote_state_contract" {
  command = plan

  override_data {
    target = data.terraform_remote_state.aws_organization
    values = {
      outputs = {
        contract = {
          ou_ids = {
            Workloads = "ou-abcd-workloads0"
          }
          account_ids = { backup = "444444444444" }
          account_role_arns = {
            backup = "arn:aws:iam::444444444444:role/cross-account"
          }
        }
      }
    }
  }

  assert {
    condition     = local.org.account_role_arns["backup"] == "arn:aws:iam::444444444444:role/cross-account"
    error_message = "remote-state account_role_arns must expose the backup role the aws.backup provider assumes"
  }

  assert {
    condition     = local.org.ou_ids["Workloads"] == "ou-abcd-workloads0"
    error_message = "remote-state ou_ids must expose the Workloads OU the org BACKUP_POLICY attaches to"
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
        contract = {
          ou_ids = {
            Workloads = "ou-abcd-workloads0"
          }
          account_ids = { backup = "444444444444" }
          account_role_arns = {
            backup = "arn:aws:iam::444444444444:role/cross-account"
          }
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
      account_ids       = { backup = "444444444444" }
      account_role_arns = { backup = "arn:aws:iam::444444444444:role/cross-account" }
      ou_ids            = { Workloads = "ou-abcd-workloads0" }
    }
  }

  assert {
    condition     = length(data.terraform_remote_state.aws_organization) == 0 && local.org.ou_ids["Workloads"] == "ou-abcd-workloads0"
    error_message = "a supplied organization_contract must skip the aws-organization read and feed the root"
  }
}
