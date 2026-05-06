# Example: create Google Workspace security groups for GCP access.
# Groups are used as IAM principals — grant roles to groups, not individuals.

locals {
  customer_id = "C0abc1234"
}

module "gcp_groups" {
  source = "../../"

  customer_id = local.customer_id

  identity_groups = [
    {
      id           = "gcp-organization-admins@example.com"
      display_name = "GCP Organization Admins"
      email        = "gcp-organization-admins@example.com"
      description  = "Members have organization-level admin access"
    },
    {
      id           = "gcp-platform-team@example.com"
      display_name = "GCP Platform Team"
      email        = "gcp-platform-team@example.com"
      description  = "Platform engineering team with Terraform access"
    },
    {
      id           = "gcp-dev-team@example.com"
      display_name = "GCP Dev Team"
      email        = "gcp-dev-team@example.com"
      description  = "Developer team with workload project access"
    },
  ]
}

output "groups" {
  description = "Created identity groups keyed by group email"
  value       = module.gcp_groups.identity_groups
}
