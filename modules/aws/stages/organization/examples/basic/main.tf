# Basic working example for the aws-organization stage.
# Uses the default foundational account set and the SRA OU/policy defaults;
# supplies the required account-qualified carve-out ARNs, the log-archive
# bucket name, the TFC organization (replace my-tfc-org), a guard-alert
# recipient and the GitHub owner pinned for app-services deploy roles (the
# stage's check blocks warn when the last two are empty). Run
# `terraform init && terraform validate` here to check it.

module "aws_organization" {
  source = "../../"

  terraform_run_role_arn  = "arn:aws:iam::111111111111:role/tfc-run-role"
  break_glass_role_arn    = "arn:aws:iam::111111111111:role/break-glass"
  log_archive_bucket_name = "sra-log-archive-111111111111"
  tfc_organization        = "my-tfc-org"

  guard_alert_emails = ["secops@example.com"]

  # Pin GitHub Actions federation to your owner: name and immutable numeric ID.
  github_federation_owners    = ["example-org"]
  github_federation_owner_ids = ["123456789"]
}
