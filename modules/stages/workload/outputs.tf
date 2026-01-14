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
