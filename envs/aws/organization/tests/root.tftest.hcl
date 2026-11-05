# Cross-root OUTPUT CONTRACT test for the aws-organization root (the PRODUCER).
#
# Downstream aws roots read organization_id / organization_root_id /
# management_account_id / ou_ids / account_ids[*] / account_role_arns[*] from
# this root via terraform_remote_state, and they configure their providers from
# account_role_arns at init time. Renaming or dropping any of these keys breaks
# every downstream root at provider-init and leaves them un-destroyable (audit
# H4). This test fails if a contract output is removed, renamed, or loses a
# foundational account key, so a refactor cannot silently break the contract.
#
# Method: override the composed stage module's outputs with a known, valid
# contract, then assert the ROOT re-exports them under the agreed names/keys.
# This tests the root's output wiring (the actual cross-root boundary) at plan,
# without depending on mock-generated resource values.

mock_provider "aws" {}

variables {
  management_account_id = "111111111111" # C4 account guard
  accounts = {                           # L2: non-placeholder emails
    log_archive      = { email = "aws+log-archive@acme.test", ou = "Security" }
    security_tooling = { email = "aws+security-tooling@acme.test", ou = "Security" }
    network          = { email = "aws+network@acme.test", ou = "Infrastructure" }
    shared_services  = { email = "aws+shared-services@acme.test", ou = "Infrastructure" }
    backup           = { email = "aws+backup@acme.test", ou = "Infrastructure" }
    forensics        = { email = "aws+forensics@acme.test", ou = "Security" }
  }
  terraform_run_role_arn  = "arn:aws:iam::111111111111:role/tfc-run-role"
  break_glass_role_arn    = "arn:aws:iam::111111111111:role/break-glass"
  log_archive_bucket_name = "ashes-org-log-archive"
}

override_module {
  target = module.aws_organization
  outputs = {
    organization_id       = "o-abcdefghij"
    management_account_id = "111111111111"
    organization_root_id  = "r-abcd"
    ou_ids = {
      "Security"       = "ou-abcd-11110000"
      "Infrastructure" = "ou-abcd-22220000"
    }
    account_ids = {
      security_tooling = "222222222222"
      log_archive      = "333333333333"
      network          = "444444444444"
      shared_services  = "555555555555"
      backup           = "666666666666"
      forensics        = "777777777777"
    }
    account_role_arns = {
      security_tooling = "arn:aws:iam::222222222222:role/OrganizationAccountAccessRole"
      log_archive      = "arn:aws:iam::333333333333:role/OrganizationAccountAccessRole"
      network          = "arn:aws:iam::444444444444:role/OrganizationAccountAccessRole"
      shared_services  = "arn:aws:iam::555555555555:role/OrganizationAccountAccessRole"
      backup           = "arn:aws:iam::666666666666:role/OrganizationAccountAccessRole"
      forensics        = "arn:aws:iam::777777777777:role/OrganizationAccountAccessRole"
    }
  }
}

run "output_contract_is_stable" {
  command = plan

  # account_role_arns must be re-exported and expose every foundational account.
  # Downstream roots index this map by account name to set their provider role_arn.
  assert {
    condition = alltrue([
      for k in ["security_tooling", "log_archive", "network", "shared_services", "backup", "forensics"] :
      contains(keys(output.account_role_arns), k)
    ])
    error_message = "account_role_arns must re-export every foundational account key (cross-root contract)."
  }

  # account_ids must re-export the same foundational accounts.
  assert {
    condition = alltrue([
      for k in ["security_tooling", "log_archive", "network", "shared_services", "backup", "forensics"] :
      contains(keys(output.account_ids), k)
    ])
    error_message = "account_ids must re-export every foundational account key (cross-root contract)."
  }

  # The scalar contract outputs must still exist and carry the stage values.
  assert {
    condition     = output.organization_id == "o-abcdefghij" && output.organization_root_id == "r-abcd" && output.management_account_id == "111111111111"
    error_message = "the aws-organization root must re-export organization_id / organization_root_id / management_account_id."
  }

  assert {
    condition     = contains(keys(output.ou_ids), "Security")
    error_message = "ou_ids must be re-exported as part of the cross-root contract."
  }
}
