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
  description = "Stable configuration contract for downstream application environments"
  sensitive   = true
  value = {
    for env_key, env in var.environments : env_key => {
      folder_id           = module.organization.folders[env_key].id
      folder_name         = module.organization.folders[env_key].display_name
      host_project_id     = module.projects.project_ids["${env_key}-host"]
      host_project_number = module.projects.project_numbers["${env_key}-host"]
      region              = env.region
      cidr_block          = env.cidr_block
      labels              = env.labels
      tag_value_ids = {
        environment = module.organization.tag_value_ids["environment-${env_key}"]
      }
    }
  }
}

# Tag Values (for downstream usage)
output "tag_values" {
  description = "Map of available Resource Manager Tag Values"
  value       = module.organization.tag_value_ids
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
