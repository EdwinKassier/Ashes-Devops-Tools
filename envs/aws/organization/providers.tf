# Phase-1 foundation root. The organization, guardrails (SCP/RCP/declarative/tag),
# foundational account vending, and centralized root-access management all run in
# the MANAGEMENT (payer) account, so this root has a SINGLE default provider and
# NO aliased providers. Region comes from var.aws_region so the same root can be
# pointed at any region without code edits.
provider "aws" {
  region = var.aws_region
}
