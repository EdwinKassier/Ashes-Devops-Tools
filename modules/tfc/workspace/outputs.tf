output "id" {
  description = "The workspace ID (ws-...)."
  value       = tfe_workspace.this.id
}

output "name" {
  description = "The workspace name."
  value       = tfe_workspace.this.name
}

output "notification_ids" {
  description = "Map of notification name to its configuration ID."
  value       = { for k, n in tfe_notification_configuration.this : k => n.id }
}

output "variable_keys" {
  description = "Sorted keys of the variables set directly on the workspace (values omitted; some are sensitive)."
  value       = sort(keys(var.variables))
}

output "variable_values" {
  description = "Values of the NON-sensitive variables set directly on the workspace, keyed by name (sensitive ones are omitted)."
  value       = { for k, v in var.variables : k => v.value if !try(v.sensitive, false) }
}

output "trigger_patterns" {
  description = "Trigger patterns configured on the workspace."
  value       = tfe_workspace.this.trigger_patterns
}

output "speculative_enabled" {
  description = "Whether automatic speculative (PR) plans are allowed."
  value       = tfe_workspace.this.speculative_enabled
}

output "remote_state_consumer_ids" {
  description = "Workspace IDs allowed to read this workspace's state as managed by this module (empty when global_remote_state = true or manage_settings = false)."
  value       = var.manage_settings && !var.global_remote_state ? sort(tolist(var.remote_state_consumer_ids)) : []
}

output "variable_set_labels" {
  description = "Labels of the variable sets attached to this workspace."
  value       = sort(keys(var.variable_set_ids))
}

output "working_directory" {
  description = "Working directory (root) the workspace runs in."
  value       = tfe_workspace.this.working_directory
}

output "auto_apply" {
  description = "Whether a successful plan applies without confirmation."
  value       = tfe_workspace.this.auto_apply
}

output "allow_destroy_plan" {
  description = "Whether destroy plans may be queued from the UI/API."
  value       = tfe_workspace.this.allow_destroy_plan
}
