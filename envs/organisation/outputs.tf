# Admin Project
output "admin_project" {
  description = "Details of the admin project"
  value = {
    project_id = google_project.admin_project.project_id
    name       = google_project.admin_project.name
    number     = google_project.admin_project.number
    labels     = google_project.admin_project.labels
  }
  sensitive = true
}

# Organization Details
output "organization" {
  description = "Organization details"
  value = {
    id           = module.organization.organization_id
    name         = module.organization.organization_name
    domain       = module.organization.organization_domain
    customer_id  = module.organization.organization_directory_customer_id
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
  value       = module.organization.projects
  sensitive   = true
}

# IAM and Policies
output "iam_policy_etag" {
  description = "The etag of the organization's IAM policy"
  value       = module.organization.iam_policy_etag
}

output "resource_locations_policy" {
  description = "Details of the resource locations organization policy"
  value       = module.organization.resource_locations_policy
  sensitive   = true
}

output "domain_restricted_sharing_policy" {
  description = "Details of the domain restricted sharing policy"
  value       = module.organization.domain_restricted_sharing_policy
  sensitive   = true
}
