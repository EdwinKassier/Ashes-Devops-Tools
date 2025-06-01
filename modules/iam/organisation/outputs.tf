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

output "domain_restricted_sharing_policy" {
  description = "Details of the domain restricted sharing policy"
  value       = google_org_policy_policy.domain_restricted_sharing
  sensitive   = true
}

# Identity Groups
output "identity_groups" {
  description = "Map of created identity groups"
  value       = module.ou_identity_groups.identity_groups
  sensitive   = true
}

# Folder IAM Bindings
output "folder_iam_bindings" {
  description = "Map of folder IAM bindings"
  value = {
    for k, v in google_folder_iam_binding.folder_iam_bindings : k => {
      folder = v.folder
      role   = v.role
      members = v.members
    }
  }
  sensitive = true
}

# Group Memberships
output "group_memberships" {
  description = "Map of group memberships"
  value       = module.ou_group_memberships.memberships
  sensitive   = true
}

# Enabled APIs
output "enabled_apis" {
  description = "List of APIs enabled in the organization"
  value       = [for api in google_project_service.required_apis : api.service]
}

# Organizational Units
output "organizational_units" {
  description = "Map of created organizational units"
  value = {
    for k, v in google_cloud_identity_group.org_units : k => {
      name  = v.name
      email = v.group_key[0].id
    }
  }
}

# Folders
output "folders" {
  description = "Map of created folders"
  value = {
    for k, v in google_folder.ou_folders : k => {
      name = v.display_name
      id   = v.name
    }
  }
}

output "projects" {
  description = "Map of created projects"
  value = {
    for k, v in google_project.projects : k => {
      project_id = v.project_id
      name       = v.name
      number     = v.number
      folder_id  = v.folder_id
      labels     = v.labels
    }
  }
  sensitive = true
}