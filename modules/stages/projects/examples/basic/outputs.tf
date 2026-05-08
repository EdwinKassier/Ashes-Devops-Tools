output "project_ids" {
  description = "Map of 'environment/project-name' to GCP project ID"
  value       = module.projects.project_ids
}
