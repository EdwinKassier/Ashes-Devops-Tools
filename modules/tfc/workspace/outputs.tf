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
