# Variable-validation tests for the aws-organization stage.
#
# Uses mock_provider so no AWS credentials are required. module.organization is
# overridden with known IDs so the accept case reaches (and passes) plan; the
# reject case fails inside the account module's email validation before any
# resource is evaluated.

mock_provider "aws" {}

variables {
  terraform_run_role_arn  = "arn:aws:iam::111111111111:role/tfc-run-role"
  break_glass_role_arn    = "arn:aws:iam::111111111111:role/break-glass"
  log_archive_bucket_name = "sra-log-archive-111111111111"
}

override_module {
  target = module.organization
  outputs = {
    organization_id       = "o-abc1234567"
    organization_arn      = "arn:aws:organizations::111111111111:organization/o-abc1234567"
    roots_id              = "r-abcd"
    management_account_id = "111111111111"
    ou_ids = {
      "Security"          = "ou-abcd-security0"
      "Infrastructure"    = "ou-abcd-infra0000"
      "Workloads"         = "ou-abcd-workload0"
      "Sandbox"           = "ou-abcd-sandbox00"
      "Suspended"         = "ou-abcd-suspend00"
      "PolicyStaging"     = "ou-abcd-policyst0"
      "Exceptions"        = "ou-abcd-except000"
      "Transitional"      = "ou-abcd-transit00"
      "Workloads/Prod"    = "ou-abcd-prod0000"
      "Workloads/NonProd" = "ou-abcd-nonprod0"
    }
  }
}

run "defaults_accepted" {
  # Accept case: the default foundational account set + required carve-out ARNs
  # must pass all validations and plan cleanly.
  command = plan
}

run "invalid_account_email_rejected" {
  # Reject case: an account with a malformed root email must fail the account
  # module's email validation.
  command = plan

  variables {
    workload_accounts = {
      broken = { email = "not-an-email", ou = "Workloads" }
    }
  }

  expect_failures = [var.workload_accounts]
}
