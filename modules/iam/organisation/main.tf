
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

# Organization IAM policy
resource "google_organization_iam_policy" "organization_policy" {
  org_id      = data.google_organization.org.org_id
  policy_data = data.google_iam_policy.admin.policy_data
}

data "google_iam_policy" "admin" {
  binding {
    role    = "roles/resourcemanager.organizationAdmin"
    members = var.org_admin_members
  }

  binding {
    role    = "roles/billing.admin"
    members = var.billing_admin_members
  }
}

# Organization policies
resource "google_org_policy_policy" "resource_locations" {
  name   = "organizations/${data.google_organization.org.org_id}/policies/gcp.resourceLocations"
  parent = "organizations/${data.google_organization.org.org_id}"

  spec {
    rules {
      values {
        allowed_values = var.allowed_regions
      }
    }
  }
}

resource "google_org_policy_policy" "domain_restricted_sharing" {
  name   = "organizations/${data.google_organization.org.org_id}/policies/iam.allowedPolicyMemberDomains"
  parent = "organizations/${data.google_organization.org.org_id}"

  spec {
    rules {
      values {
        allowed_values = ["C:/${split("@", var.domain)[0]}"]
      }
    }
  }
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
}

# Create Projects in each OU folder
# checkov:skip=CKV2_GCP_5:Audit logging is configured at org level via cloud-audit-logs module
resource "google_project" "projects" {
  for_each = {
    for proj_key, proj in flatten([
      for ou_key, ou in var.organizational_units : [
        for proj_key, proj in lookup(ou, "projects", {}) : {
          ou_key      = ou_key
          proj_key    = proj_key
          proj        = proj
          folder_name = ou_key
        }
      ]
    ]) : "${proj.ou_key}_${proj_key}" => proj
  }

  name            = each.value.proj.name
  project_id      = "${each.value.proj.name}-${each.value.ou_key}"
  folder_id       = google_folder.ou_folders[each.value.ou_key].name
  billing_account = each.value.proj.billing_account
  labels = merge(
    var.project_labels,
    lookup(each.value.proj, "labels", {}),
    {
      environment = each.value.ou_key
      folder_name = each.value.folder_name
    }
  )

  depends_on = [
    google_cloud_identity_group.org_units,
    google_folder.ou_folders
  ]
}

# Enable required services for each project
resource "google_project_service" "project_services" {
  for_each = {
    for proj in google_project.projects : proj.project_id => proj
  }

  project = each.value.project_id
  service = "cloudresourcemanager.googleapis.com"

  disable_dependent_services = false
  disable_on_destroy         = false
}

# Create identity groups for each organizational unit
module "ou_identity_groups" {
  source = "../../iam/identity_group"

  customer_id = var.customer_id
  identity_groups = [
    {
      id           = "dev-admins"
      display_name = "Development Administrators"
      email        = "gcp-dev-admins@${var.domain}"
      description  = "Administrators for Development environment"
    },
    {
      id           = "dev-developers"
      display_name = "Development Developers"
      email        = "gcp-dev-developers@${var.domain}"
      description  = "Developers for Development environment"
    },
    {
      id           = "uat-admins"
      display_name = "UAT Administrators"
      email        = "gcp-uat-admins@${var.domain}"
      description  = "Administrators for UAT environment"
    },
    {
      id           = "uat-developers"
      display_name = "UAT Developers"
      email        = "gcp-uat-developers@${var.domain}"
      description  = "Developers for UAT environment"
    },
    {
      id           = "prod-admins"
      display_name = "Production Administrators"
      email        = "gcp-prod-admins@${var.domain}"
      description  = "Administrators for Production environment"
    },
    {
      id           = "prod-developers"
      display_name = "Production Developers"
      email        = "gcp-prod-developers@${var.domain}"
      description  = "Developers for Production environment"
    }
  ]
}

# Create IAM bindings for each identity group at the folder level
resource "google_folder_iam_binding" "folder_iam_bindings" {
  for_each = {
    "dev-admins" = {
      folder = "development"
      role   = "roles/editor"
    },
    "dev-developers" = {
      folder = "development"
      role   = "roles/viewer"
    },
    "uat-admins" = {
      folder = "uat"
      role   = "roles/editor"
    },
    "uat-developers" = {
      folder = "uat"
      role   = "roles/viewer"
    },
    "prod-admins" = {
      folder = "production"
      role   = "roles/editor"
    },
    "prod-developers" = {
      folder = "production"
      role   = "roles/viewer"
    }
  }


  folder = google_folder.ou_folders[each.value.folder].name
  role   = each.value.role
  members = [
    "group:${module.ou_identity_groups.identity_groups[each.key].email}"
  ]

  depends_on = [
    module.ou_identity_groups,
    google_folder.ou_folders
  ]
}

# Create group memberships for each identity group
module "ou_group_memberships" {
  source = "../../iam/identity_group_memberships"

  members = [
    # Development Admins
    {
      group_id  = module.ou_identity_groups.identity_groups["dev-admins"].name
      member_id = var.admin_email
      roles     = ["MEMBER", "MANAGER"]
    },
    # Development Developers
    {
      group_id  = module.ou_identity_groups.identity_groups["dev-developers"].name
      member_id = var.developers_group_email
      roles     = ["MEMBER"]
    },
    # UAT Admins
    {
      group_id  = module.ou_identity_groups.identity_groups["uat-admins"].name
      member_id = var.admin_email
      roles     = ["MEMBER", "MANAGER"]
    },
    # UAT Developers
    {
      group_id  = module.ou_identity_groups.identity_groups["uat-developers"].name
      member_id = var.developers_group_email
      roles     = ["MEMBER"]
    },
    # Production Admins
    {
      group_id  = module.ou_identity_groups.identity_groups["prod-admins"].name
      member_id = var.admin_email
      roles     = ["MEMBER", "MANAGER"]
    },
    # Production Developers
    {
      group_id  = module.ou_identity_groups.identity_groups["prod-developers"].name
      member_id = var.developers_group_email
      roles     = ["MEMBER"]
    }
  ]

  depends_on = [
    module.ou_identity_groups
  ]
}

# Outputs have been moved to outputs.tf