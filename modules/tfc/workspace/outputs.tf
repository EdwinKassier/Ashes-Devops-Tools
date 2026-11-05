output "id" {
  description = "The workspace ID (ws-...)."
  value       = tfe_workspace.this.id
}

output "name" {
  description = "The workspace name."
  value       = tfe_workspace.this.name
}
