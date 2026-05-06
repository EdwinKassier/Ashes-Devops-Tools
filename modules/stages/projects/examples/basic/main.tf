# Example: create environment project hierarchies under org folders.
# In a full deployment this is invoked from envs/organization/main.tf.
# The folders and suffix inputs come from the organization and bootstrap stages.

locals {
  admin_project_id = "myorg-tf-admin-abc123"
  billing_account  = "ABCDEF-123456-789012"
  suffix           = "abc123"

  # Folders output from modules/stages/organization.
  folders = {
    dev = {
      id           = "123456789001"
      name         = "folders/123456789001"
      display_name = "Development"
    }
    prod = {
      id           = "123456789002"
      name         = "folders/123456789002"
      display_name = "Production"
    }
  }
}

module "projects" {
  source = "../../"

  project_prefix          = "myorg"
  organization_name       = "myorg"
  default_billing_account = local.billing_account
  admin_project_id        = local.admin_project_id
  suffix                  = local.suffix
  folders                 = local.folders

  environments = {
    dev = {
      display_name = "Development"
      description  = "Development environment"
      projects = {
        "api" = {
          name   = "api"
          labels = { team = "backend" }
        }
      }
    }
    prod = {
      display_name = "Production"
      description  = "Production environment"
      projects = {
        "api" = {
          name   = "api"
          labels = { team = "backend" }
        }
      }
    }
  }
}

output "project_ids" {
  description = "Map of 'environment/project-name' to GCP project ID"
  value       = module.projects.project_ids
}
