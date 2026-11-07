# A real root re-exports the stage module's output contract — the stable keys
# that DOWNSTREAM roots consume via terraform_remote_state (Convention 4).
# outputs.tf must NEVER be left empty in a live root: it is the cross-root API.
# Keep output keys stable across refactors; renaming a key breaks every reader.
# Replace / extend the output below with this root's real contract.
#
# Downstream roots read ONE output, `contract`: a non-sensitive object holding
# every key they may consume (they read .outputs.contract, nothing else). Never
# put a sensitive value in it: one sensitive attribute moves the whole object
# into tfe_outputs' sensitive_values. Give the output the exact object type: the
# conversion drops any key the type does not name. If downstream roots read this
# layer, add it to PRODUCERS in scripts/check-contracts.sh (which then requires
# the type and compares its keys with local.contract).

locals {
  contract = {
    upstream = local.upstream
  }
}

output "contract" {
  description = "This root's cross-root contract: one non-sensitive object downstream roots read as .outputs.contract."
  # Replace `any` with the real shape once the root has one.
  type = object({
    upstream = any
  })
  value = local.contract
}

output "upstream_contract" {
  description = "The organization contract this root resolved (variable, config file or <cloud>-organization remote state)."
  value       = local.upstream
}
