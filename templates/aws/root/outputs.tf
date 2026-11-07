# A real root re-exports the stage module's output contract — the stable keys
# that DOWNSTREAM roots consume via terraform_remote_state (Convention 4).
# outputs.tf must NEVER be left empty in a live root: it is the cross-root API.
#
# Keep output keys stable across refactors; renaming a key breaks every root
# that reads it. Replace / extend the outputs below with this root's real ones.
#
# Downstream roots read ONE output, `contract`: a non-sensitive object holding
# every key they may consume (they read .outputs.contract, nothing else). Never
# put a sensitive value in it: one sensitive attribute moves the whole object
# into tfe_outputs' sensitive_values. Give the output the exact object type: the
# conversion drops any key the type does not name. If downstream roots read this
# layer, add it to PRODUCERS in scripts/check-contracts.sh (which then requires
# the type and compares its top-level keys with local.contract; nested
# attributes are not compared, so add those to the type by hand).

locals {
  contract = {
    account_ids = local.account_ids
    aws_region  = local.aws_region
  }
}

output "contract" {
  description = "This root's cross-root contract: one non-sensitive object downstream roots read as .outputs.contract."
  type = object({
    account_ids = map(string)
    aws_region  = string
  })
  value = local.contract
}

output "account_ids" {
  description = "Map of account key -> AWS account ID this root resolved from the organization contract (variable, config file or aws-organization remote state)."
  value       = local.account_ids
}

output "aws_region" {
  description = "Effective primary region (variable > config file > eu-west-2)."
  value       = local.aws_region
}
