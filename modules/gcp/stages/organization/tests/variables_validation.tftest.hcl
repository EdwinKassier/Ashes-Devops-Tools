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
  domain                = "example.com"
  org_id                = "123456789"
  admin_project_id      = "mock-admin-project"
  admin_project_number  = "123456789012"
  customer_id           = "C01abc123"
  terraform_admin_email = "terraform-admin@mock-admin-project.iam.gserviceaccount.com"
  billing_account       = "ABCDEF-123456-789012"
  project_prefix        = "my-org"
  default_region        = "europe-west1"
  monthly_budget_amount = 1000
  environments = {
    dev = {
      display_name            = "Development"
      description             = "Development environment"
      iam_group_role_bindings = {}
    }
  }
  gcp = {
    admin_email                           = "admin@example.com"
    organization_admin_groups             = ["org-admins@example.com"]
    billing_admin_groups                  = ["billing-admins@example.com"]
    allowed_regions                       = ["europe-west1", "europe-west4"]
    strict_folder_policy_environment_keys = ["prod"]
    security_contact_email                = "security@example.com"
    billing_contact_email                 = "billing@example.com"
    budget_currency                       = "USD"
    alert_notification_emails             = ["secops@example.com"]
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


# monthly_budget_amount = 0 means "no budget cap" (billing alerts disabled) — valid since v21.
run "accepts_zero_budget" {
  command = plan
  override_module {
    target  = module.cmek
    outputs = { keyring_id = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek", keyring_name = "my-org-org-cmek", key_ids = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }, key_names = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" } }
  }
  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "example.com", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
  }
  variables {
    monthly_budget_amount = 0
  }
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
  variables {
    monthly_budget_amount = -100
  }
}

run "rejects_lowercase_currency" {
  command         = plan
  expect_failures = [var.gcp]
  override_module {
    target  = module.cmek
    outputs = { keyring_id = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek", keyring_name = "my-org-org-cmek", key_ids = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }, key_names = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" } }
  }
  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "example.com", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
  }
  variables {
    gcp = merge(var.gcp, {
      budget_currency = "usd"
    })
  }
}

run "rejects_invalid_currency_length" {
  command         = plan
  expect_failures = [var.gcp]
  override_module {
    target  = module.cmek
    outputs = { keyring_id = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek", keyring_name = "my-org-org-cmek", key_ids = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }, key_names = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" } }
  }
  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "example.com", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
  }
  variables {
    gcp = merge(var.gcp, {
      budget_currency = "US"
    })
  }
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
  expect_failures = [var.gcp]
  override_module {
    target  = module.cmek
    outputs = { keyring_id = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek", keyring_name = "my-org-org-cmek", key_ids = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }, key_names = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" } }
  }
  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "example.com", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
  }
  variables {
    gcp = merge(var.gcp, {
      allowed_regions = []
    })
  }
}

run "rejects_invalid_security_email" {
  command         = plan
  expect_failures = [var.gcp]
  override_module {
    target  = module.cmek
    outputs = { keyring_id = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek", keyring_name = "my-org-org-cmek", key_ids = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }, key_names = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" } }
  }
  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "example.com", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
  }
  variables {
    gcp = merge(var.gcp, {
      security_contact_email = "not-an-email"
    })
  }
}

# admin_email has no default: unset in both gcp_overrides and gcp.admin_email
# (config/landing-zone.yaml) fails the plan.
run "rejects_unset_admin_email" {
  command         = plan
  expect_failures = [var.gcp]
  override_module {
    target  = module.cmek
    outputs = { keyring_id = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek", keyring_name = "my-org-org-cmek", key_ids = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }, key_names = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" } }
  }
  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "example.com", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
  }
  variables {
    gcp = merge(var.gcp, {
      admin_email = null
    })
  }
}

run "rejects_invalid_billing_email" {
  command         = plan
  expect_failures = [var.gcp]
  override_module {
    target  = module.cmek
    outputs = { keyring_id = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek", keyring_name = "my-org-org-cmek", key_ids = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }, key_names = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" } }
  }
  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "example.com", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
  }
  variables {
    gcp = merge(var.gcp, {
      billing_contact_email = "missing-at-sign"
    })
  }
}

run "rejects_os_login_exemption_of_strict_folder" {
  command = plan
  override_module {
    target  = module.cmek
    outputs = { keyring_id = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek", keyring_name = "my-org-org-cmek", key_ids = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }, key_names = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" } }
  }
  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "example.com", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
  }
  variables {
    gcp = merge(var.gcp, {
      os_login_exempt_environment_keys = ["prod"]
    })
  }
  expect_failures = [var.gcp]
}

run "rejects_prefixed_org_admin_group" {
  command = plan
  override_module {
    target  = module.cmek
    outputs = { keyring_id = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek", keyring_name = "my-org-org-cmek", key_ids = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }, key_names = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" } }
  }
  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "example.com", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
  }
  variables {
    gcp = merge(var.gcp, {
      organization_admin_groups = ["user:alice@example.com"]
    })
  }
  expect_failures = [var.gcp]
}

run "rejects_empty_org_admin_groups_without_escape" {
  command = plan
  override_module {
    target  = module.cmek
    outputs = { keyring_id = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek", keyring_name = "my-org-org-cmek", key_ids = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }, key_names = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" } }
  }
  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "example.com", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
  }
  variables {
    gcp = merge(var.gcp, {
      organization_admin_groups = []
    })
  }
  expect_failures = [var.gcp]
}

run "rejects_admin_user_listed_as_group" {
  command = plan
  override_module {
    target  = module.cmek
    outputs = { keyring_id = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek", keyring_name = "my-org-org-cmek", key_ids = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }, key_names = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" } }
  }
  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "example.com", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
  }
  variables {
    gcp = merge(var.gcp, {
      organization_admin_groups = ["admin@example.com"]
    })
  }
  expect_failures = [var.gcp]
}

run "rejects_pam_without_approvers" {
  command = plan
  override_module {
    target  = module.cmek
    outputs = { keyring_id = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek", keyring_name = "my-org-org-cmek", key_ids = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }, key_names = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" } }
  }
  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "example.com", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
  }
  variables {
    gcp = merge(var.gcp, {
      enable_pam          = true
      pam_eligible_groups = ["requesters@example.com"]
    })
  }
  expect_failures = [var.gcp]
}

run "rejects_pam_self_approval" {
  command = plan
  override_module {
    target  = module.cmek
    outputs = { keyring_id = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek", keyring_name = "my-org-org-cmek", key_ids = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }, key_names = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" } }
  }
  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "example.com", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
  }
  variables {
    gcp = merge(var.gcp, {
      enable_pam          = true
      pam_eligible_groups = ["admins@example.com"]
      pam_approver_groups = ["admins@example.com"]
    })
  }
  expect_failures = [var.gcp]
}

run "rejects_owner_in_delegated_folder_roles" {
  command = plan
  override_module {
    target  = module.cmek
    outputs = { keyring_id = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek", keyring_name = "my-org-org-cmek", key_ids = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }, key_names = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" } }
  }
  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "example.com", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
  }
  variables {
    delegated_workload_folder_roles = ["roles/owner"]
  }
  expect_failures = [var.delegated_workload_folder_roles]
}

run "rejects_unknown_guardrail_owner_mode" {
  command         = plan
  expect_failures = [var.gcp]
  override_module {
    target  = module.cmek
    outputs = { keyring_id = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek", keyring_name = "my-org-org-cmek", key_ids = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }, key_names = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" } }
  }
  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "example.com", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
  }
  variables {
    gcp = merge(var.gcp, {
      guardrail_owner_mode = "nobody"
    })
  }
}

run "rejects_short_log_analytics_retention" {
  command         = plan
  expect_failures = [var.gcp]
  override_module {
    target  = module.cmek
    outputs = { keyring_id = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek", keyring_name = "my-org-org-cmek", key_ids = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }, key_names = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" } }
  }
  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "example.com", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
  }
  variables {
    gcp = merge(var.gcp, {
      log_analytics_retention_days = 30
    })
  }
}

run "rejects_malformed_logging_settings_kms_key" {
  command         = plan
  expect_failures = [var.gcp]
  override_module {
    target  = module.cmek
    outputs = { keyring_id = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek", keyring_name = "my-org-org-cmek", key_ids = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }, key_names = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" } }
  }
  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "example.com", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
  }
  variables {
    gcp = merge(var.gcp, {
      logging_settings_kms_key_name = "not-a-key"
    })
  }
}

run "override_key_with_prefix_rejected" {
  command = plan

  variables {
    gcp = merge(var.gcp, {
      org_policy_overrides = { "constraints/compute.requireOsLogin" = { enforce = false } }
    })
  }

  expect_failures = [var.gcp]
  override_module {
    target  = module.cmek
    outputs = { keyring_id = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek", keyring_name = "my-org-org-cmek", key_ids = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }, key_names = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" } }
  }
  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "example.com", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
  }
}

run "non_https_issuer_rejected" {
  command = plan

  variables {
    gcp = merge(var.gcp, {
      allowed_workload_identity_issuers = ["http://evil.example"]
    })
  }

  expect_failures = [var.gcp]
  override_module {
    target  = module.cmek
    outputs = { keyring_id = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek", keyring_name = "my-org-org-cmek", key_ids = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" }, key_names = { "audit-logs" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-logs", "audit-analytics" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/audit-analytics", "billing-alerts" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-alerts", "scc-notifications" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/scc-notifications", "billing-export" = "projects/mock-admin-project/locations/europe-west1/keyRings/my-org-org-cmek/cryptoKeys/billing-export" } }
  }
  override_module {
    target  = module.organization
    outputs = { organization_id = "123456789", organization_name = "organizations/123456789", organization_domain = "example.com", organization_directory_customer_id = "C01abc123", folder_iam_members = {}, enabled_apis = [], organizational_units = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } }, folders = { dev = { id = "folders/111111111", name = "folders/111111111", display_name = "Development" } } }
  }
}
