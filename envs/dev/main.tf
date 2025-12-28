# This file demonstrates how to piggyback on the organization setup
# The provider is already configured to impersonate the Terraform Admin SA

# We can access the remote state of the organization to get folder IDs if needed
# But typically we might pass them in or use data sources.
# For this scaffold, we'll just demonstrate a simple resource creation.

variable "project_prefix" {
  description = "Prefix used in organization setup"
  type        = string
  default     = "my-org"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
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
  # Extract the host project ID for the 'dev' environment from the organization outputs
  # Structure: environment_config[env][projects][project_key][project_id]
  dev_host_project_id = data.terraform_remote_state.organization.outputs.environment_config[var.environment].projects["host"].project_id
}

# Use the retrieved Project ID
data "google_project" "dev_host_project" {
  project_id = local.dev_host_project_id
}

# Example resource to verify detailed permissions
resource "google_storage_bucket" "dev_state_bucket" {
  name          = "${var.project_prefix}-dev-state-${data.google_project.dev_host_project.number}"
  location      = "EU"
  project       = data.google_project.dev_host_project.project_id
  force_destroy = true

  uniform_bucket_level_access = true
}
