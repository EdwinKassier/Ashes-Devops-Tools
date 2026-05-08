# Example: provision the org-level resources — folder hierarchy, IAM groups,
# tags, org policies, and CMEK keys for the landing zone.
# In a full deployment this is invoked from envs/organization/main.tf.
# Replace locals with bootstrap outputs or remote state references.

locals {
  org_id                = "123456789012"
  admin_project_id      = "myorg-tf-admin-abc123"
  admin_project_number  = "987654321098"
  customer_id           = "C0abc1234"
  billing_account       = "ABCDEF-123456-789012"
  terraform_admin_email = "terraform@myorg-tf-admin-abc123.iam.gserviceaccount.com"
}

module "organization" {
  source = "../../"

  domain                = "example.com"
  org_id                = local.org_id
  admin_project_id      = local.admin_project_id
  admin_project_number  = local.admin_project_number
  customer_id           = local.customer_id
  admin_email           = "infra-admin@example.com"
  terraform_admin_email = local.terraform_admin_email
  billing_account       = local.billing_account
  project_prefix        = "myorg"

  environments = {
    dev = {
      display_name            = "Development"
      description             = "Development environment"
      iam_group_role_bindings = {}
    }
    prod = {
      display_name            = "Production"
      description             = "Production environment"
      iam_group_role_bindings = {}
    }
  }

  organization_admin_groups             = ["group:gcp-organization-admins@example.com"]
  billing_admin_groups                  = ["group:gcp-billing-admins@example.com"]
  default_region                        = "us-central1"
  allowed_regions                       = ["us-central1", "us-east1", "europe-west1"]
  strict_folder_policy_environment_keys = ["prod"]
  security_contact_email                = "security@example.com"
  billing_contact_email                 = "billing@example.com"
  monthly_budget_amount                 = 1000
  budget_currency                       = "USD"
}
