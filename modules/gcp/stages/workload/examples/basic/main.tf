# Example: onboard a new service team project into the landing zone.
#
# This example creates a GCP project for a service team, enables common APIs,
# attaches it to the environment's Shared VPC host project, and grants the
# team's admin group least-privilege IAM roles. In the landing zone
# stages/environment calls this module once per var.service_teams entry.
# Replace all locals with real values or remote state.

locals {
  # Service account the providers impersonate (versions.tf).
  terraform_sa    = "terraform@my-seed-project.iam.gserviceaccount.com"
  org_id          = "123456789012"
  billing_account = "ABCDEF-123456-789012"

  # Folder for the service team environment (created by envs/gcp/organization)
  folder_id = "987654321098"

  # The environment's Shared VPC host project (gcp-projects environment_config
  # host project) and the subnets the team may use.
  host_project_id = "myorg-dev-host"
  subnets = {
    private = {
      region      = "us-central1"
      subnet_name = "private-us-central1"
    }
  }

  # IAM admin group for this service team: the bare email (the module adds the
  # "group:" prefix).
  team_admin_group = "team-backend-admins@example.com"
}

module "backend_service_project" {
  source = "../../"

  project_name    = "backend-service"
  org_id          = local.org_id
  folder_id       = local.folder_id
  billing_account = local.billing_account

  activate_apis = [
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
  ]

  labels = {
    team        = "backend"
    environment = "dev"
    managed_by  = "terraform"
  }

  # Shared VPC attachment
  enable_shared_vpc_attachment = true
  shared_vpc_host_project_id   = local.host_project_id
  shared_vpc_subnets           = local.subnets

  # Grant least-privilege roles to the team admin group.
  # Bindings use google_project_iam_member (additive) — other members holding
  # these roles are preserved on every apply; Terraform will not evict them.
  project_admin_group_email = local.team_admin_group
  project_admin_roles = [
    "roles/run.developer",
    "roles/artifactregistry.writer",
    "roles/logging.viewer",
  ]
}
