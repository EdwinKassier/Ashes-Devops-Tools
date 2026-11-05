output "project_id" {
  description = "The project ID. Depends on API enablement, so consumers wait until var.services are live."
  value       = google_project.this.project_id
  depends_on  = [google_project_service.this]
}

output "number" {
  description = "The numeric project number."
  value       = google_project.this.number
  depends_on  = [google_project_service.this]
}

output "name" {
  description = "The project display name."
  value       = google_project.this.name
}

output "id" {
  description = "The project resource ID (projects/<project_id>)."
  value       = google_project.this.id
}

output "parent" {
  description = "The parent the project was created under (folders/<id> or organizations/<id>)."
  value       = var.parent
}

output "labels" {
  description = "The labels applied to the project."
  value       = google_project.this.labels
}

output "billing_account" {
  description = "The billing account linked to the project (null if none)."
  value       = google_project.this.billing_account
}

output "services" {
  description = "Sorted list of APIs this module enables on the project."
  value       = sort(keys(google_project_service.this))
}

output "shared_vpc_host_project_id" {
  description = "The Shared VPC host project this project is attached to (null when not attached)."
  value       = one(google_compute_shared_vpc_service_project.this[*].host_project)
}
