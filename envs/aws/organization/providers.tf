# Phase-1 foundation root. The organization, guardrails (SCP/RCP/declarative/tag),
# foundational account vending, and centralized root-access management all run in
# the MANAGEMENT (payer) account, so this root has a SINGLE default provider and
# NO aliased providers. Region comes from var.aws_region so the same root can be
# pointed at any region without code edits.
provider "aws" {
  region = var.aws_region
  # C4: fail fast if the resolved credentials are not the management (payer)
  # account. This root creates org-level resources (org, SCPs, account factory);
  # a mis-set AWS_PROFILE or TFC run role must never deploy them into the wrong
  # account. Admins set management_account_id to their own payer account.
  allowed_account_ids = [var.management_account_id]
}
