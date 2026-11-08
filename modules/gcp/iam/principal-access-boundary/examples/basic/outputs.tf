output "policy_name" {
  description = "Full resource name of the principal access boundary policy."
  value       = module.automation_boundary.policy_name
}

output "bound_principal_sets" {
  description = "Binding key to the principal set bound to the boundary."
  value       = module.automation_boundary.bound_principal_sets
}
