output "workspace_ids" {
  description = "Map of workspace name to its TFC workspace ID (ws-...)."
  value       = { for k, m in module.workspace : k => m.id }
}

output "workspace_names" {
  description = "The set of managed workspace names."
  value       = sort(keys(module.workspace))
}
