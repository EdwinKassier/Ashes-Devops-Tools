# Example: a service project under a folder, with the APIs it needs, an
# additive IAM grant for its owning team and a security contact. The naming
# scheme (prefix / env / suffix) is the CALLER's: the module uses project_id
# verbatim.

module "project" {
  source = "../../"

  project_id      = var.project_id
  name            = "Acme App Dev"
  parent          = "folders/${var.folder_id}"
  billing_account = var.billing_account

  labels = {
    environment = "dev"
    team        = "app"
    managed-by  = "terraform"
  }

  services = [
    "compute.googleapis.com",
    "essentialcontacts.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ]

  # Optional: attach as a Shared VPC service project.
  shared_vpc_host_project_id = var.shared_vpc_host_project_id

  iam = {
    "roles/logging.viewer" = ["group:app-team@example.com"]
  }

  essential_contacts = {
    "secops@example.com" = ["SECURITY", "TECHNICAL"]
  }
}
