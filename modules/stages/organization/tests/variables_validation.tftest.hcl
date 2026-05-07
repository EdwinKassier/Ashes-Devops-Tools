# Variable validation tests for the stages/organization module.
# All runs use mock_provider so no GCP credentials are required.
#
# Every run includes override_module for module.cmek and module.organization
# because Terraform evaluates child module variable validations in parallel
# with top-level variable validations. Without overrides, the mock_provider
# returns bare strings for KMS key names and numeric-only org IDs, causing
# additional failures that would mask the variable under test.

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

run "accepts_positive_budget" {
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

  variables {
    monthly_budget_amount = 500
  }
}

run "rejects_zero_budget" {
  command         = plan
  expect_failures = [var.monthly_budget_amount]
  override_module {
    target  = module.cmek
    outputs = { keyring_id = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek", keyring_name = "my-org-org-cmek", key_ids = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }, key_names = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" } }
  }
  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "example.com", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
  }
  variables { monthly_budget_amount = 0 }
}

run "rejects_negative_budget" {
  command         = plan
  expect_failures = [var.monthly_budget_amount]
  override_module {
    target  = module.cmek
    outputs = { keyring_id = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek", keyring_name = "my-org-org-cmek", key_ids = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }, key_names = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" } }
  }
  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "example.com", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
  }
  variables { monthly_budget_amount = -100 }
}

run "rejects_lowercase_currency" {
  command         = plan
  expect_failures = [var.budget_currency]
  override_module {
    target  = module.cmek
    outputs = { keyring_id = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek", keyring_name = "my-org-org-cmek", key_ids = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }, key_names = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" } }
  }
  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "example.com", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
  }
  variables { budget_currency = "usd" }
}

run "rejects_invalid_currency_length" {
  command         = plan
  expect_failures = [var.budget_currency]
  override_module {
    target  = module.cmek
    outputs = { keyring_id = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek", keyring_name = "my-org-org-cmek", key_ids = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }, key_names = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" } }
  }
  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "example.com", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
  }
  variables { budget_currency = "US" }
}

run "rejects_empty_environments" {
  command         = plan
  expect_failures = [var.environments]
  override_module {
    target  = module.cmek
    outputs = { keyring_id = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek", keyring_name = "my-org-org-cmek", key_ids = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }, key_names = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" } }
  }
  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "example.com", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
  }
  variables {
    environments = {}
  }
}

run "rejects_empty_allowed_regions" {
  command         = plan
  expect_failures = [var.allowed_regions]
  override_module {
    target  = module.cmek
    outputs = { keyring_id = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek", keyring_name = "my-org-org-cmek", key_ids = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }, key_names = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" } }
  }
  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "example.com", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
  }
  variables {
    allowed_regions = []
  }
}

run "rejects_invalid_security_email" {
  command         = plan
  expect_failures = [var.security_contact_email]
  override_module {
    target  = module.cmek
    outputs = { keyring_id = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek", keyring_name = "my-org-org-cmek", key_ids = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }, key_names = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" } }
  }
  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "example.com", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
  }
  variables {
    security_contact_email = "not-an-email"
  }
}

run "rejects_invalid_billing_email" {
  command         = plan
  expect_failures = [var.billing_contact_email]
  override_module {
    target  = module.cmek
    outputs = { keyring_id = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek", keyring_name = "my-org-org-cmek", key_ids = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }, key_names = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" } }
  }
  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "example.com", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
  }
  variables {
    billing_contact_email = "missing-at-sign"
  }
}
