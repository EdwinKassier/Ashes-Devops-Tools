output "policy_name" {
  description = "Full resource name of the principal access boundary policy."
  value       = google_iam_principal_access_boundary_policy.this.name
}

output "policy_id" {
  description = "ID of the principal access boundary policy."
  value       = var.policy_id
}

output "boundary_resources" {
  description = "Resources the bound principals may act on."
  value       = local.boundary_resources
}

output "binding_ids" {
  description = "Map of binding key => policy binding ID."
  value       = { for k, b in google_iam_projects_policy_binding.this : k => b.policy_binding_id }
}

output "bound_principal_sets" {
  description = "Map of binding key => principal set bound to the boundary."
  value       = { for k, p in var.project_bindings : k => "//cloudresourcemanager.googleapis.com/projects/${p}" }
}
