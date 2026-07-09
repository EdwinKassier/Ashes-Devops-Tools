# Plan-assertion tests for the aws-organization stage.
#
# Uses mock_provider so no AWS credentials are required. module.organization is
# overridden with known root/OU/organization IDs so that (a) the guardrail
# attachment for_each targets and the org-identity/account-id inputs to the
# policy module are known at plan, and (b) the assertions on plan-known output
# keys are non-vacuous.

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

run "composes_accounts_and_guardrails" {
  command = plan

  assert {
    condition     = contains(keys(output.account_ids), "security_tooling")
    error_message = "the security_tooling foundational account must be created"
  }

  assert {
    condition     = contains(keys(output.account_ids), "forensics")
    error_message = "the forensics foundational account must be created"
  }

  assert {
    condition     = length(keys(output.account_ids)) >= 6
    error_message = "at least the six foundational accounts must be created"
  }

  assert {
    condition     = contains(keys(output.policy_attachment_ids), "deny-tamper@root")
    error_message = "the deny-tamper guardrail must be attached to the root"
  }

  assert {
    condition     = length(output.policy_attachment_ids) >= 6
    error_message = "at least six guardrail attachments must be created"
  }
}
