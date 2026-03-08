
# Data source for the organization
data "google_organization" "org" {
  domain = var.domain
}

# Enable required organization level APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "orgpolicy.googleapis.com"
  ])

  project                    = var.project_id
  service                    = each.key
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Organization IAM members (non-authoritative - preserves existing IAM)
resource "google_organization_iam_member" "org_admins" {
  for_each = toset(var.org_admin_members)

  org_id = data.google_organization.org.org_id
  role   = "roles/resourcemanager.organizationAdmin"
  member = each.value
}

resource "google_organization_iam_member" "billing_admins" {
  for_each = toset(var.billing_admin_members)

  org_id = data.google_organization.org.org_id
  role   = "roles/billing.admin"
  member = each.value
}

resource "google_folder" "ou_folders" {
  for_each     = var.organizational_units
  display_name = each.value.display_name
  parent       = "organizations/${data.google_organization.org.org_id}"

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  folder_iam_bindings = {
    for binding in flatten([
      for ou_key, ou in var.organizational_units : [
        for group_email, roles in ou.iam_group_role_bindings : [
          for role in roles : {
            key         = "${ou_key}-${substr(md5("${group_email}:${role}"), 0, 12)}"
            folder_key  = ou_key
            group_email = group_email
            role        = role
          }
        ]
      ]
    ]) : binding.key => binding
  }
}

resource "google_folder_iam_member" "folder_iam_members" {
  for_each = local.folder_iam_bindings

  folder = google_folder.ou_folders[each.value.folder_key].name
  role   = each.value.role
  member = "group:${each.value.group_email}"

  depends_on = [google_folder.ou_folders]
}
