output "role_id" {
  description = "The ID of the created custom role"
  value       = google_project_iam_custom_role.custom_role.role_id
}

output "name" {
  description = "The resource name of the created custom role"
  value       = google_project_iam_custom_role.custom_role.name
}

output "title" {
  description = "The human-readable title of the custom role"
  value       = google_project_iam_custom_role.custom_role.title
}

output "stage" {
  description = "The current launch stage of the role"
  value       = google_project_iam_custom_role.custom_role.stage
} 