
# Data source for the organization
data "google_organization" "org" {
  domain = var.domain
}

# Enable required organization level APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "cloudidentity.googleapis.com",
    "orgpolicy.googleapis.com"
  ])

  project                    = var.project_id
  service                    = each.key
  disable_dependent_services = false
  disable_on_destroy         = false
}

# Organization IAM members (non-authoritative - preserves existing IAM)
# Using google_organization_iam_member instead of google_organization_iam_policy
# to avoid accidentally removing existing IAM bindings
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


# Create Organizational Units
resource "google_cloud_identity_group" "org_units" {
  for_each = var.organizational_units

  display_name = each.value.display_name
  description  = lookup(each.value, "description", "")
  parent       = "customers/${var.customer_id}"

  group_key {
    id = "${each.key}@${var.domain}"
  }


  labels = {
    "cloudidentity.googleapis.com/groups.discussion_forum" = ""
  }

  depends_on = [google_project_service.required_apis]
}

# Create Folders for each OU
resource "google_folder" "ou_folders" {
  for_each     = var.organizational_units
  display_name = each.value.display_name
  parent       = "organizations/${data.google_organization.org.org_id}"

  lifecycle {
    prevent_destroy = true
  }
}



# Create identity groups for each organizational unit
module "ou_identity_groups" {
  source = "../../iam/identity_group"

  customer_id = var.customer_id
  identity_groups = flatten([
    for ou_key, ou in var.organizational_units : [
      for group_key, group in(ou.groups != null ? ou.groups : {}) : {
        id           = "${ou_key}-${group_key}"
        display_name = "${ou.display_name} ${group_key}"
        email        = "gcp-${ou_key}-${group_key}@${var.domain}"
        description  = group.description != null ? group.description : "${group_key} for ${ou.display_name} environment"
      }
    ]
  ])
}

# Create IAM members for each identity group at the folder level (non-authoritative)
# Using google_folder_iam_member instead of google_folder_iam_binding to preserve
# any existing IAM bindings not managed by Terraform
resource "google_folder_iam_member" "folder_iam_members" {
  for_each = {
    for member in flatten([
      for ou_key, ou in var.organizational_units : [
        for group_key, group in(ou.groups != null ? ou.groups : {}) : {
          key      = "${ou_key}-${group_key}"
          folder   = ou_key
          role     = group.role
          group_id = "${ou_key}-${group_key}"
        }
      ]
    ]) : member.key => member
  }

  folder = google_folder.ou_folders[each.value.folder].name
  role   = each.value.role
  member = "group:${module.ou_identity_groups.identity_groups[each.value.group_id].group_key[0].id}"

  depends_on = [
    module.ou_identity_groups,
    google_folder.ou_folders
  ]
}

# Create group memberships for each identity group
module "ou_group_memberships" {
  source = "../../iam/identity_group_memberships"

  members = flatten([
    for ou_key, ou in var.organizational_units : flatten([
      for group_key, group in(ou.groups != null ? ou.groups : {}) : [
        for member_email in lookup(var.group_defaults, group_key, []) : {
          group_id  = module.ou_identity_groups.identity_groups["${ou_key}-${group_key}"].name
          member_id = member_email
          roles     = ["MEMBER"]
        }
      ]
    ])
  ])

  depends_on = [
    module.ou_identity_groups
  ]
}