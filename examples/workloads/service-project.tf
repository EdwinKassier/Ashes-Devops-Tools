# Copy this snippet into a dedicated workload root.
# Replace the variable and remote-state references with the equivalents from your own composition.

module "workload_api_service" {
  source = "../../modules/stages/workload"

  project_name = "${var.project_prefix}-${var.environment}-api"

  org_id          = data.terraform_remote_state.organization.outputs.org_id
  folder_id       = data.terraform_remote_state.organization.outputs.environment_config[var.environment].folder_id
  billing_account = data.terraform_remote_state.organization.outputs.billing_account

  project_admin_group_email = "gcp-${var.environment}-platform@example.com"

  enable_shared_vpc_attachment = true
  shared_vpc_host_project_id   = data.terraform_remote_state.organization.outputs.environment_config[var.environment].host_project_id
  shared_vpc_subnets = {
    private = {
      region      = data.terraform_remote_state.organization.outputs.environment_config[var.environment].region
      subnet_name = "replace-with-private-subnet-name"
    }
  }

  project_admin_roles = [
    "roles/storage.admin",
    "roles/bigquery.admin"
  ]

  labels = {
    environment = var.environment
    team        = "platform"
    app         = "api-service"
  }
}
