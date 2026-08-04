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
  backup_role_arn          = "arn:aws:iam::111111111111:role/aws-backup-role"
  restore_testing_role_arn = "arn:aws:iam::444444444444:role/backup-restore-test"
}

run "consumes_remote_state_contract" {
  command = plan

  override_data {
    target = data.terraform_remote_state.aws_organization
    values = {
      outputs = {
        ou_ids = {
          Workloads = "ou-abcd-workloads0"
        }
        account_role_arns = {
          backup = "arn:aws:iam::444444444444:role/cross-account"
        }
      }
    }
  }

  assert {
    condition     = data.terraform_remote_state.aws_organization.outputs.account_role_arns["backup"] == "arn:aws:iam::444444444444:role/cross-account"
    error_message = "remote-state account_role_arns must expose the backup role the aws.backup provider assumes"
  }

  assert {
    condition     = data.terraform_remote_state.aws_organization.outputs.ou_ids["Workloads"] == "ou-abcd-workloads0"
    error_message = "remote-state ou_ids must expose the Workloads OU the org BACKUP_POLICY attaches to"
  }
}
