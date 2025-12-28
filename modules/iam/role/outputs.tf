output "role_id" {
  description = "The ID of the created custom role"
  value = var.level == "project" ? (
    length(google_project_iam_custom_role.project_role) > 0 ?
    google_project_iam_custom_role.project_role[0].role_id : null
    ) : (
    length(google_organization_iam_custom_role.org_role) > 0 ?
    google_organization_iam_custom_role.org_role[0].role_id : null
  )
}

output "name" {
  description = "The resource name of the created custom role"
  value = var.level == "project" ? (
    length(google_project_iam_custom_role.project_role) > 0 ?
    google_project_iam_custom_role.project_role[0].name : null
    ) : (
    length(google_organization_iam_custom_role.org_role) > 0 ?
    google_organization_iam_custom_role.org_role[0].name : null
  )
}

output "title" {
  description = "The human-readable title of the custom role"
  value       = var.title
}

output "stage" {
  description = "The current launch stage of the role"
  value       = var.stage
}

output "permissions" {
  description = "The list of permissions granted by this role"
  value       = var.permissions
}

output "level" {
  description = "The level at which the role was created (project or organization)"
  value       = var.level
}