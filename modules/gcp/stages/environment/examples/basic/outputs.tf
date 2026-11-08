output "network_name" {
  description = "Name of the environment spoke VPC."
  value       = module.environment.network_name
}

output "service_team_project_ids" {
  description = "Service team key to project ID."
  value       = module.environment.service_team_project_ids
}

output "app_github_actions" {
  description = "Per-service variables for the GitHub Actions delivery workflow."
  value       = module.environment.app_github_actions
}

output "components" {
  description = "Plan-time summary of which components the environment creates."
  value       = module.environment.components
}
