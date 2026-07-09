# A real root re-exports the stage module's output contract — the stable keys
# that DOWNSTREAM roots consume via terraform_remote_state (Convention 4).
# outputs.tf must NEVER be left empty in a live root: it is the cross-root API.
# Keep output keys stable across refactors; renaming a key breaks every reader.
#
# output "<contract_key>" {
#   description = "Stable value downstream roots read via remote state."
#   value       = module.stage.<contract_key>
# }
