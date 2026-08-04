# Regression test for tag-binding parent formatting.
# Asserts that google_tags_tag_binding.environment.parent is a full resource name
# (//cloudresourcemanager.googleapis.com/folders/<id>) as required by the provider.
#
# Uses mock_provider plus override_module for module.organization (non-empty folders)
# and module.tags (matching tag_values) so at least one binding is planned — an empty
# set would make alltrue([]) vacuously true (see Testing Conventions).

mock_provider "google" {}

variables {
  domain                                = "example.com"
  org_id                                = "123456789"
  admin_project_id                      = "mock-admin-project"
  admin_project_number                  = "123456789012"
  customer_id                           = "C01abc123"
  admin_email                           = "admin@example.com"
  terraform_admin_email                 = "terraform-admin@mock-admin-project.iam.gserviceaccount.com"
  billing_account                       = "ABCDEF-123456-789012"
  project_prefix                        = "my-org"
  organization_admin_groups             = ["org-admins@example.com"]
  billing_admin_groups                  = ["billing-admins@example.com"]
  default_region                        = "europe-west1"
  allowed_regions                       = ["europe-west1", "europe-west4"]
  strict_folder_policy_environment_keys = ["prod"]
  security_contact_email                = "security@example.com"
  billing_contact_email                 = "billing@example.com"
  monthly_budget_amount                 = 1000
  budget_currency                       = "USD"
  environments = {
    dev = {
      display_name            = "Development"
      description             = "Development environment"
      iam_group_role_bindings = {}
    }
  }
}

run "tag_binding_parent_is_full_resource_name" {
  command = plan

  override_module {
    target = module.cmek
    outputs = {
      keyring_id   = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek"
      keyring_name = "my-org-org-cmek"
      key_ids      = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }
      key_names    = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }
    }
  }
  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "example.com", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
  }
  override_module {
    target  = module.tags
    outputs = { tag_keys = { "environment" = "tagKeys/111", "business-unit" = "tagKeys/222", "data-classification" = "tagKeys/333" }, tag_values = { "environment-dev" = "tagValues/999" } }
  }

  assert {
    # length check first — alltrue([]) is vacuously true, so an empty set would false-pass
    condition = length(google_tags_tag_binding.environment) > 0 && alltrue([
      for b in google_tags_tag_binding.environment :
      startswith(b.parent, "//cloudresourcemanager.googleapis.com/folders/")
    ])
    error_message = "tag binding parent must be a full resource name (//cloudresourcemanager.googleapis.com/folders/<id>) and at least one binding must be planned"
  }
}
