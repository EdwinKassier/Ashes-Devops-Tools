# Organization Information
output "organization_id" {
  description = "The numeric ID of the organization"
  value       = data.google_organization.org.org_id
}

output "organization_name" {
  description = "The resource name of the organization"
  value       = data.google_organization.org.name
}

output "organization_domain" {
  description = "The domain of the organization"
  value       = data.google_organization.org.domain
}

output "organization_directory_customer_id" {
  description = "The directory customer ID of the organization"
  value       = data.google_organization.org.directory_customer_id
}
output "folder_iam_members" {
  description = "Map of folder IAM members"
  value = {
    for k, v in google_folder_iam_member.folder_iam_members : k => {
      folder = v.folder
      role   = v.role
      member = v.member
    }
  }
}

# Enabled APIs
output "enabled_apis" {
  description = "List of APIs enabled in the organization"
  value       = [for api in google_project_service.required_apis : api.service]
}

# Folders (created from the organizational_units input)
output "folders" {
  description = "Map of created folders (keyed by organizational-unit key)"
  value = {
    for k, v in google_folder.ou_folders : k => {
      id           = v.folder_id
      name         = v.name
      display_name = v.display_name
    }
  }
}
