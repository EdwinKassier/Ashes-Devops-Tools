# A real root re-exports the stage module's output contract — the stable keys
# that DOWNSTREAM roots consume via terraform_remote_state (Convention 4).
# outputs.tf must NEVER be left empty in a live root: it is the cross-root API.
#
# Keep output keys stable across refactors; renaming a key breaks every root
# that reads it. Replace / extend the outputs below with this root's real ones.

output "account_ids" {
  description = "Map of account key -> AWS account ID this root resolved from the organization contract (variable, config file or aws-organization remote state)."
  value       = local.account_ids
}

output "aws_region" {
  description = "Effective primary region (variable > config file > eu-west-2)."
  value       = local.aws_region
}
