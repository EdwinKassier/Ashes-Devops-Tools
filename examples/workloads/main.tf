# Example: attach a service project to Shared VPC using the workload module.
# In a real deployment replace the locals below with data sources or remote state.

locals {
  org_id          = "123456789"
  folder_id       = "111111111"
  billing_account = "ABCDEF-123456-789012"
  host_project_id = "my-host-project"
  region          = "europe-west1"
  private_subnet  = "private-subnet-europe-west1"
}

module "workload_api_service" {
  source = "../../modules/stages/workload"

  project_name = "${var.project_prefix}-${var.environment}-api"

  org_id          = local.org_id
  folder_id       = local.folder_id
  billing_account = local.billing_account

  project_admin_group_email = "gcp-${var.environment}-platform@example.com"

  enable_shared_vpc_attachment = true
  shared_vpc_host_project_id   = local.host_project_id
  shared_vpc_subnets = {
    private = {
      region      = local.region
      subnet_name = local.private_subnet
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
