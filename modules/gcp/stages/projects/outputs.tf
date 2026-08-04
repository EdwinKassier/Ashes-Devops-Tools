output "projects" {
  description = "Map of created projects"
  value       = google_project.projects
}

output "project_ids" {
  description = "Map of Project IDs"
  value       = { for k, v in google_project.projects : k => v.project_id }
}

output "project_numbers" {
  description = "Map of Project Numbers"
  value       = { for k, v in google_project.projects : k => v.number }
}
