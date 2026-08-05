# Variable validation tests for the aws/incident-response module.
# aws is mocked; the archive provider runs for real during init.

mock_provider "aws" {}

run "valid_inputs_accepted" {
  command = plan

  variables {
    forensics_account_id = "333333333333"
    org_id               = "o-abc123def0"
  }
}

run "bad_forensics_account_id_rejected" {
  # Reject case: a non-12-digit account id must trip the validation while
  # incident response is enabled.
  command = plan

  variables {
    forensics_account_id = "12345"
    org_id               = "o-abc123def0"
  }

  expect_failures = [var.forensics_account_id]
}
