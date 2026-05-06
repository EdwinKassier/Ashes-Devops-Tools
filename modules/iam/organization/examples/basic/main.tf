# Example: grant org-level admin roles to dedicated Google Groups.
# Use groups rather than individual user accounts to keep IAM policy surface
# stable as team membership changes.

locals {
  project_id = "my-seed-project"
}

module "org_iam" {
  source = "../../"

  domain      = "example.com"
  project_id  = local.project_id
  customer_id = "C0abc1234"

  org_admin_members = [
    "group:gcp-organization-admins@example.com",
  ]

  billing_admin_members = [
    "group:gcp-billing-admins@example.com",
    "user:finance-lead@example.com",
  ]
}

output "organization_id" {
  description = "The numeric GCP organization ID"
  value       = module.org_iam.organization_id
}
