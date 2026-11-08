output "urls" {
  description = "Cloud Run service URL per service (internal ingress only)."
  value       = module.app_services.urls
}

output "sql_connection_names" {
  description = "Cloud SQL connection name per service that declares a database."
  value       = module.app_services.sql_connection_names
}

output "github_actions" {
  description = "Per-service variables for the GitHub Actions delivery workflow."
  value       = module.app_services.github_actions
}
