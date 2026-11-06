/**
 * Copyright 2023 Ashes
 *
 * VPC Service Controls Module - Outputs
 */

# Standard interface outputs
output "id" {
  description = "The ID of the service perimeter"
  value = var.perimeter_type == "PERIMETER_TYPE_REGULAR" ? (
    length(google_access_context_manager_service_perimeter.perimeter) > 0 ?
    google_access_context_manager_service_perimeter.perimeter[0].id : null
    ) : (
    length(google_access_context_manager_service_perimeter.bridge) > 0 ?
    google_access_context_manager_service_perimeter.bridge[0].id : null
  )
}

output "self_link" {
  description = "The self_link of the service perimeter"
  value = var.perimeter_type == "PERIMETER_TYPE_REGULAR" ? (
    length(google_access_context_manager_service_perimeter.perimeter) > 0 ?
    google_access_context_manager_service_perimeter.perimeter[0].name : null
    ) : (
    length(google_access_context_manager_service_perimeter.bridge) > 0 ?
    google_access_context_manager_service_perimeter.bridge[0].name : null
  )
}

output "name" {
  description = "The resource name of the service perimeter"
  value = var.perimeter_type == "PERIMETER_TYPE_REGULAR" ? (
    length(google_access_context_manager_service_perimeter.perimeter) > 0 ?
    google_access_context_manager_service_perimeter.perimeter[0].name : null
    ) : (
    length(google_access_context_manager_service_perimeter.bridge) > 0 ?
    google_access_context_manager_service_perimeter.bridge[0].name : null
  )
}

output "access_policy_name" {
  description = "The name of the access policy"
  value       = local.access_policy_name
}

output "access_policy" {
  description = "The created access policy resource (if created)"
  value       = var.create_access_policy ? google_access_context_manager_access_policy.policy[0] : null
}

output "access_levels" {
  description = "Map of created access levels"
  value       = google_access_context_manager_access_level.levels
}

output "perimeter" {
  description = "The service perimeter resource"
  value = var.perimeter_type == "PERIMETER_TYPE_REGULAR" ? (
    length(google_access_context_manager_service_perimeter.perimeter) > 0 ?
    google_access_context_manager_service_perimeter.perimeter[0] : null
    ) : (
    length(google_access_context_manager_service_perimeter.bridge) > 0 ?
    google_access_context_manager_service_perimeter.bridge[0] : null
  )
}

output "protected_project_numbers" {
  description = "List of project numbers protected by this perimeter"
  value       = var.protected_projects
}

output "enforced" {
  description = "True when the perimeter has an enforced status (enable_dry_run = false)."
  value       = !var.enable_dry_run
}

output "dry_run_spec_staged" {
  description = "True when an enforced perimeter also carries a staged dry-run spec (any dry_run_* override set)."
  value       = local.stage_dry_run_spec
}
