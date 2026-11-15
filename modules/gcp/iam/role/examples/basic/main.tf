# Example: create a custom project-level IAM role with a minimal permission set.
# Use custom roles to implement least-privilege where predefined roles are too broad.

locals {
  project_id = "my-workload-project"
}

module "cloud_run_deployer" {
  source = "../../"

  level       = "project"
  project_id  = local.project_id
  role_id     = "cloudRunDeployer"
  title       = "Cloud Run Deployer"
  description = "Allows deploying new Cloud Run service revisions without accessing secrets or IAM bindings"

  permissions = [
    "run.services.create",
    "run.services.update",
    "run.services.get",
    "run.services.list",
    "run.revisions.get",
    "run.revisions.list",
    # Deploying a revision that runs as a service account needs actAs on it.
    # The Cloud Run service agent, not the deployer, pulls the image.
    "iam.serviceAccounts.actAs",
  ]
}
