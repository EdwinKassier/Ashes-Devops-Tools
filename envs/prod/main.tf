# Production Environment
# Consumes infrastructure from the Organization layer via Remote State

variable "project_prefix" {
  description = "Prefix used in organization setup"
  type        = string
  default     = "my-org"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

# Fetch downstream configuration from the Organization Workspace
data "terraform_remote_state" "organization" {
  backend = "cloud"
  config = {
    organization = "example-org-please-update" # User must update this
    workspaces = {
      name = "organization-prod"
    }
  }
}

locals {
  # Extract the host project ID for the 'prod' environment from the organization outputs
  host_project_id = data.terraform_remote_state.organization.outputs.environment_config[var.environment].projects["host"].project_id
}

# Use the retrieved Project ID
data "google_project" "host_project" {
  project_id = local.host_project_id
}

# Example: Create a production usage logic (e.g., GKE or Compute) here
# For now, just verifying access with a simple bucket
resource "google_storage_bucket" "state_bucket" {
  name          = "${var.project_prefix}-${var.environment}-state-${data.google_project.host_project.number}"
  location      = "EU"
  project       = data.google_project.host_project.project_id
  
  # Production hardening
  force_destroy = false
  uniform_bucket_level_access = true
  versioning {
    enabled = true
  }
}
