output "id" {
  description = "ID of the workspace (ws-...)."
  value       = module.workspace.id
}

output "name" {
  description = "Name of the workspace."
  value       = module.workspace.name
}

output "trigger_patterns" {
  description = "Glob patterns that trigger a run in the workspace."
  value       = module.workspace.trigger_patterns
}
