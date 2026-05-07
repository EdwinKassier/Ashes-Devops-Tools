/**
 * Copyright 2023 Ashes
 *
 * Workload Factory Module - Outputs
 */

output "project_id" {
  description = "The ID of the created project"
  value       = module.project.project_id
}

output "project_number" {
  description = "The numeric identifier of the created project"
  value       = module.project.project_number
}

output "service_account_email" {
  description = "The email of the default service account"
  value       = module.project.service_account_email
}

output "subnet_iam_bindings" {
  description = "Map of subnet key to IAM binding resource ID for the networkUser bindings granted to this service project"
  value       = { for k, v in google_compute_subnetwork_iam_binding.network_users : k => v.id }
}

output "host_project_id" {
  description = "The Shared VPC host project ID this service project is attached to (null if Shared VPC attachment is disabled)"
  value       = var.enable_shared_vpc_attachment ? var.shared_vpc_host_project_id : null
}
