# Google Cloud Custom IAM Role Module
# Supports both project-level and organization-level custom roles

# Project-level custom role
resource "google_project_iam_custom_role" "project_role" {
  count = var.level == "project" ? 1 : 0

  project     = var.project_id
  role_id     = var.role_id
  title       = var.title
  description = var.description
  permissions = var.permissions
  stage       = var.stage
}

# Organization-level custom role
resource "google_organization_iam_custom_role" "org_role" {
  count = var.level == "organization" ? 1 : 0

  org_id      = var.org_id
  role_id     = var.role_id
  title       = var.title
  description = var.description
  permissions = var.permissions
  stage       = var.stage
}