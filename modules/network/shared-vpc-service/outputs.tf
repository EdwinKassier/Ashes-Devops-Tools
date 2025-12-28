/**
 * Copyright 2023 Ashes
 *
 * Shared VPC Service Project Module - Outputs
 */

# Standard interface outputs
output "id" {
  description = "The ID of the shared VPC service project attachment"
  value       = google_compute_shared_vpc_service_project.service_project.id
}

output "self_link" {
  description = "The ID of the shared VPC service project attachment"
  value       = google_compute_shared_vpc_service_project.service_project.id
}

# Service project outputs
output "service_project" {
  description = "The shared VPC service project attachment resource"
  value       = google_compute_shared_vpc_service_project.service_project
}

output "host_project_id" {
  description = "The host project ID"
  value       = var.host_project_id
}

output "service_project_id" {
  description = "The service project ID"
  value       = var.service_project_id
}

output "service_project_number" {
  description = "The service project number"
  value       = data.google_project.service_project.number
}

# IAM outputs
output "subnet_iam_members" {
  description = "The subnet IAM member bindings"
  value       = google_compute_subnetwork_iam_member.subnet_users
}

output "network_user_members" {
  description = "The project-level network user IAM members"
  value       = google_project_iam_member.network_users
}
