# A real root re-exports the stage module's output contract — the stable keys
# that DOWNSTREAM roots consume via terraform_remote_state (Convention 4).
# outputs.tf must NEVER be left empty in a live root: it is the cross-root API.
#
# Keep output keys stable across refactors; renaming a key breaks every root
# that reads it. Replace the stub below with this root's real outputs.
#
# output "account_role_arns" {
#   description = "Map of foundational-account name -> assume-role ARN, consumed by downstream aws roots."
#   value       = module.workload.account_role_arns
# }
