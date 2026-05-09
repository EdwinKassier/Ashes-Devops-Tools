# Example: onboard a new service team project into the landing zone.
#
# This example creates a GCP project for a service team, enables common APIs,
# attaches it to the Shared VPC host project, and grants the team's admin group
# least-privilege IAM roles. Replace all locals with real values or remote state.

locals {
  terraform_sa    = "terraform@my-seed-project.iam.gserviceaccount.com"
  org_id          = "123456789012"
  billing_account = "ABCDEF-123456-789012"

  # Folder for the service team environment (created by envs/organization)
  folder_id = "987654321098"

  # Hub network project and subnet details (from envs/organization outputs or remote state)
  hub_project_id = "my-hub-project"
  subnets = {
    private = {
      region      = "us-central1"
      subnet_name = "private-us-central1"
    }
  }

  # IAM admin group for this service team
  team_admin_group = "group:team-backend-admins@example.com"
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
  shared_vpc_host_project_id   = local.hub_project_id
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
