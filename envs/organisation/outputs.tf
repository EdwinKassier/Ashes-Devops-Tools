# Billing Account
output "billing_account" {
  description = "Billing account ID for downstream usage"
  value       = data.google_billing_account.billing.id
  sensitive   = true
}

# Admin Project
output "admin_project" {
  description = "Details of the admin project"
  value = {
    project_id = module.bootstrap.admin_project_id
    number     = module.bootstrap.admin_project_number
  }
  sensitive = true
}

# Admin Project Number (for VPC-SC ingress policies referencing Workload Identity)
output "admin_project_number" {
  description = "Admin project number for Workload Identity pool references"
  value       = module.bootstrap.admin_project_number
}

# Organization Details
output "organization" {
  description = "Organization details"
  value = {
    id = module.organization.organization_id
    # Accessing other org details might need module output updates if required
  }
  sensitive = true
}

# Organization ID (for VPC-SC and other resources requiring org_id)
output "org_id" {
  description = "Organization ID for downstream resource configuration"
  value       = module.organization.organization_id
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
      # Auto-assign CIDR: 10.{10 + index}.0.0/16
      # This allocates 10.10.x.x, 10.11.x.x, etc. based on alphabetical order of keys (dev, prod, uat...)
      # 'dev' -> index 0 -> 10.10.x.x
      # 'prod' -> index 1 -> 10.11.x.x
      # 'uat' -> index 2 -> 10.12.x.x
      cidr_block = (
        try(var.environments[env_key].cidr_block, null) != null
        ? var.environments[env_key].cidr_block
        : format("10.%d.0.0/16", 10 + index(keys(module.organization.folders), env_key))
      )
      projects = {
        for proj_key, proj_id in module.projects.project_ids :
        trimprefix(proj_key, "${env_key}-") => {
          project_id     = proj_id
          project_number = module.projects.project_numbers[proj_key]
        }
        if startswith(proj_key, env_key)
      }
      # Centralized region configuration for downstream consumption
      region = var.default_region
    }
  }
}

# Tag Values (for downstream usage)
output "tag_values" {
  description = "Map of available Resource Manager Tag Values"
  value       = module.organization.tags
}

# Network Hub Details (for Peering)
output "hub_network" {
  description = "Hub Network details for peering"
  value = {
    vpc_self_link = module.network_hub.hub_vpc_self_link
    vpc_name      = module.network_hub.hub_vpc_name
    dns_zone_name = module.network_hub.dns_zone_name
    dns_domain    = module.network_hub.hub_dns_domain
  }
}

