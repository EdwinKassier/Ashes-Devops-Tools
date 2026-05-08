output "project_id" {
  description = "The GCP project ID of the created service project"
  value       = module.backend_service_project.project_id
}

output "project_number" {
  description = "The numeric project number (used for service agent identities)"
  value       = module.backend_service_project.project_number
}

output "subnet_iam_bindings" {
  description = "IAM binding resource IDs for the networkUser grants on each subnet"
  value       = module.backend_service_project.subnet_iam_bindings
}
