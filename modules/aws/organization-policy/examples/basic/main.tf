# Basic working example for the aws/organization-policy module.
# Uses the built-in guardrail set (all defaults) and attaches the baseline SCP
# and data-perimeter RCP to the org root. Run `terraform init && terraform
# validate` here to check it.

module "organization_policy" {
  source = "../../"

  org_id                  = "o-abc1234567"
  management_account_id   = "111111111111"
  security_account_id     = "222222222222"
  terraform_run_role_arn  = "arn:aws:iam::111111111111:role/tfc-run-role"
  break_glass_role_arn    = "arn:aws:iam::111111111111:role/break-glass"
  log_archive_bucket_name = "sra-log-archive-111111111111"

  attachments = [
    { policy_key = "scp-baseline", target_id = "r-abcd" },
    { policy_key = "rcp-data-perimeter", target_id = "r-abcd" },
  ]
}
