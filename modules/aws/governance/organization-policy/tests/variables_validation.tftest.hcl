# Variable validation tests for the aws/organization-policy module.
# All runs use mock_provider so no AWS credentials are required.
# Validation blocks fire before resource evaluation.

mock_provider "aws" {}

variables {
  org_id                  = "o-abc1234567"
  terraform_run_role_arn  = "arn:aws:iam::111111111111:role/tfc-run-role"
  break_glass_role_arn    = "arn:aws:iam::111111111111:role/break-glass"
  log_archive_bucket_name = "sra-log-archive-111111111111"
}

run "defaults_accepted" {
  # Accept case: valid required inputs must pass all validations.
  command = plan
}

run "invalid_org_id_rejected" {
  # Reject case: an org ID that is not of the form o-xxxx must fail validation.
  command = plan

  variables {
    org_id = "not-an-org-id"
  }

  expect_failures = [var.org_id]
}

run "unqualified_run_role_arn_rejected" {
  # Reject case: a run-role ARN with a wildcard account must fail validation
  # (carve-out ARNs must be account-qualified exact ARNs).
  command = plan

  variables {
    terraform_run_role_arn = "arn:aws:iam::*:role/tfc-run-role"
  }

  expect_failures = [var.terraform_run_role_arn]
}

run "wildcard_pipeline_role_name_rejected" {
  # Reject case: a bare "*" pipeline role name would exempt every principal.
  command = plan

  variables {
    pipeline_role_names = ["*"]
  }

  expect_failures = [var.pipeline_role_names]
}

run "invalid_trusted_account_id_rejected" {
  # Reject case: trusted perimeter accounts must be 12-digit account IDs.
  command = plan

  variables {
    data_perimeter_trusted_account_ids = ["not-an-account"]
  }

  expect_failures = [var.data_perimeter_trusted_account_ids]
}

run "wildcard_break_glass_name_rejected" {
  # Reject case: a wildcard break-glass name would widen the sole destructive carve-out.
  command = plan

  variables {
    break_glass_role_names = ["break-*"]
  }

  expect_failures = [var.break_glass_role_names]
}
