# This file contains the main configuration for the organization structure
# Provider configurations are in providers.tf

# Create admin project at the organization level
resource "google_project" "admin_project" {
  name            = "${var.project_prefix}-admin"
  project_id      = "${var.project_prefix}-admin-${random_id.suffix.hex}"
  billing_account = var.billing_account
  labels = {
    environment = "admin"
    purpose     = "administration"
    managed-by  = "terraform"
  }
}

# Random suffix to ensure unique project IDs
resource "random_id" "suffix" {
  byte_length = 4
}

module "organization" {
  source = "../../modules/iam/organisation"

  domain        = var.domain
  project_id    = google_project.admin_project.project_id
  customer_id   = var.customer_id
  billing_account = var.billing_account

  # Default organization admins
  org_admin_members = [
    "user:admin@${var.domain}",
    "group:gcp-organization-admins@${var.domain}"
  ]

  # Default billing admins
  billing_admin_members = [
    "user:billing@${var.domain}",
    "group:gcp-billing-admins@${var.domain}"
  ]

  # Allowed regions for resource creation
  allowed_regions = ["europe-west1", "europe-west2", "us-central1"]

  # Organizational Units and Projects
  organizational_units = {
    development = {
      display_name = "Development"
      description  = "Development environment"
      projects = {
        "shared" = {
          name            = "${var.project_prefix}-dev-shared"
          billing_account = var.billing_account
          labels = {
            environment = "development"
            purpose     = "shared-services"
          }
        }
        "applications" = {
          name            = "${var.project_prefix}-dev-apps"
          billing_account = var.billing_account
          labels = {
            environment = "development"
            purpose     = "applications"
          }
        }
      }
    }
    uat = {
      display_name = "UAT"
      description  = "User Acceptance Testing"
      projects = {
        "shared" = {
          name            = "${var.project_prefix}-uat-shared"
          billing_account = var.billing_account
          labels = {
            environment = "uat"
            purpose     = "shared-services"
          }
        }
        "applications" = {
          name            = "${var.project_prefix}-uat-apps"
          billing_account = var.billing_account
          labels = {
            environment = "uat"
            purpose     = "applications"
          }
        }
      }
    }
    production = {
      display_name = "Production"
      description  = "Production environment"
      projects = {
        "shared" = {
          name            = "${var.project_prefix}-prod-shared"
          billing_account = var.billing_account
          labels = {
            environment = "production"
            purpose     = "shared-services"
          }
        }
        "applications" = {
          name            = "${var.project_prefix}-prod-apps"
          billing_account = var.billing_account
          labels = {
            environment = "production"
            purpose     = "applications"
          }
        }
      }
    }
  }

  # Common labels for all projects
  project_labels = {
    managed-by   = "terraform"
    owner        = "platform-team"
    organization = var.organization_name
  }
}
