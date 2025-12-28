# Admin Project
output "admin_project" {
  description = "Details of the admin project"
  value = {
    project_id = module.bootstrap.admin_project_id
    number     = module.bootstrap.admin_project_number
  }
  sensitive = true
}

# Organization Details
output "organization" {
  description = "Organization details"
  value = {
    id          = module.organization.organization_id
    # Accessing other org details might need module output updates if required
  }
  sensitive = true
}

# Folders
output "folders" {
  description = "Map of created folders"
  value       = module.organization.folders
  sensitive   = true
}

# Projects
output "projects" {
  description = "Map of created projects"
  value       = module.projects.projects
  sensitive   = true
}

# Environment Variables
output "project_prefix" {
  description = "Project prefix used for naming"
  value       = var.project_prefix
}

output "organization_name" {
  description = "Name of the organization"
  value       = var.organization_name
}

output "default_region" {
  description = "Default region for resources"
  value       = var.default_region
}

# Service Accounts
output "terraform_service_account_email" {
  description = "Email of the Terraform Admin Service Account"
  value       = module.bootstrap.terraform_admin_email
}

# Unified environment configuration for downstream consumption
output "environment_config" {
  description = "Complete configuration for downstream environments"
  sensitive   = true
  value = {
    for env_key, folder in module.organization.folders : env_key => {
      folder_id   = folder.id
      folder_name = folder.display_name
      projects = {
        for proj_key, proj_id in module.projects.project_ids :
        trimprefix(proj_key, "${env_key}-") => {
          project_id     = proj_id
          project_number = module.projects.project_numbers[proj_key]
        }
        if startswith(proj_key, env_key)
      }
    }
  }
}

# Tag Values (for downstream usage)
output "tag_values" {
  description = "Map of available Resource Manager Tag Values"
  value       = module.organization.tags
}
