# Host stage (governance) outputs. Part of modules/gcp/stages/host.

# =============================================================================
# SHARED VPC SERVICE PROJECT OUTPUTS
# =============================================================================

output "shared_vpc_service_projects" {
  description = "All Shared VPC service project attachment outputs"
  value       = module.shared_vpc_service_projects
}

output "shared_vpc_service_project_ids" {
  description = "The IDs of all Shared VPC service project attachments"
  value = {
    for k, v in module.shared_vpc_service_projects : k => v.id
  }
}

# =============================================================================
# VPC SERVICE CONTROLS OUTPUTS
# =============================================================================

output "vpc_service_controls" {
  description = "All VPC Service Controls perimeter outputs"
  value       = module.vpc_service_controls
}

output "vpc_service_control_perimeter_names" {
  description = "The names of all VPC Service Controls perimeters"
  value = {
    for k, v in module.vpc_service_controls : k => v.name
  }
}

