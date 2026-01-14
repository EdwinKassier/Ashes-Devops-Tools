/**
 * Workload Factory Configuration
 *
 * This file demonstrates how to onboard a new service project (workload)
 * and attach it to the Production Shared VPC Host.
 * 
 * IMPORTANT: Production workloads should be carefully reviewed before deployment.
 */

# Example Workload: Core Backend Service
module "workload_core_backend" {
  source = "../../modules/stages/workload"

  project_name = "${var.project_prefix}-prod-core"

  # Organization / Billing Context
  org_id          = data.terraform_remote_state.organization.outputs.org_id
  folder_id       = local.config.folder_id
  billing_account = data.terraform_remote_state.organization.outputs.billing_account

  # Team Access
  # IMPORTANT: Replace with your organization's Google Group email.
  # This group grants roles/editor and roles/iam.serviceAccountUser to members.
  # Recommended pattern: gcp-{env}-{team}@yourdomain.com
  project_admin_group_email = "gcp-prod-admins@ashes.com" # TODO: Replace with actual team group

  # Shared VPC Attachment
  enable_shared_vpc_attachment = true
  shared_vpc_host_project_id   = local.host_project_id

  # Network Access (Subnets)
  # Granting the workload service accounts access to specific subnets
  shared_vpc_subnets = [
    {
      region      = local.config.region
      subnet_name = values(module.host.subnets["private"])[0].name # Dynamically grab the first private subnet
    }
  ]

  labels = {
    environment = var.environment
    team        = "platform"
    app         = "core-backend"
    criticality = "high"
  }
}
