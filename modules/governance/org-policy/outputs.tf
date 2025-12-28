# -----------------------------------------------------------------------------
# Policy Outputs
# -----------------------------------------------------------------------------

output "boolean_policy_names" {
  description = "Map of boolean policy constraint names to their full resource names"
  value       = { for k, v in google_org_policy_policy.boolean_policies : k => v.name }
}

output "list_policy_names" {
  description = "Map of list policy constraint names to their full resource names"
  value       = { for k, v in google_org_policy_policy.list_policies : k => v.name }
}

output "enforced_boolean_policies" {
  description = "List of boolean policies that are enforced (enforce = true)"
  value       = [for p in var.boolean_policies : p.constraint if p.enforce]
}

output "disabled_boolean_policies" {
  description = "List of boolean policies that are disabled (enforce = false)"
  value       = [for p in var.boolean_policies : p.constraint if !p.enforce]
}

output "parent" {
  description = "The parent resource where policies are applied"
  value       = var.parent
}

output "custom_constraints" {
  description = "Map of created custom constraints"
  value       = { for k, v in google_org_policy_custom_constraint.custom_constraints : k => v.name }
}
