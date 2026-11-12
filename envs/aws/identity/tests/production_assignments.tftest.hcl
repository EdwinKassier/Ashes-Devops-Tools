# CMP-14: broad write permission sets (default Developer, PowerUserAccess) are
# refused in production workload accounts.

mock_provider "aws" {
  mock_data "aws_ssoadmin_instances" {
    defaults = {
      arns               = ["arn:aws:sso:::instance/ssoins-0000000000000000"]
      identity_store_ids = ["d-0000000000"]
    }
  }
  mock_data "aws_identitystore_group" {
    defaults = { group_id = "11111111-2222-3333-4444-555555555555" }
  }
}

variables {
  landing_zone_name        = "acme"
  landing_zone_config_path = "tests/fixtures/landing-zone.prod-accounts.yaml"
}

run "production_accounts_from_config" {
  command = plan

  assert {
    condition     = length(local.production_account_keys) == 1 && contains(local.production_account_keys, "workload_prod")
    error_message = "only the account_key of an is_production: true workload environment is production."
  }
}

run "developer_group_in_prod_fails" {
  command = plan

  variables {
    identity_groups = {
      "app-developers" = [{ permission_set = "Developer", accounts = ["workload_prod"] }]
    }
  }

  expect_failures = [terraform_data.production_assignment_guard]
}

run "developer_explicit_account_id_in_prod_fails" {
  command = plan

  variables {
    assignments = {
      devs = { permission_set = "Developer", group_display_name = "app-developers", account_id = "055555555555" }
    }
  }

  expect_failures = [terraform_data.production_assignment_guard]
}

run "developer_explicit_account_key_in_prod_fails" {
  command = plan

  variables {
    assignments = {
      devs = { permission_set = "Developer", group_display_name = "app-developers", account_key = "workload_prod" }
    }
  }

  expect_failures = [terraform_data.production_assignment_guard]
}

run "developer_in_dev_passes" {
  command = plan

  variables {
    identity_groups = {
      "app-developers" = [{ permission_set = "Developer", accounts = ["workload_dev"] }]
      "app-readers"    = [{ permission_set = "ReadOnly", accounts = ["workload_prod"] }]
    }
  }

  assert {
    condition     = length(local.restricted_production_assignments) == 0
    error_message = "Developer in a non-production account and ReadOnly in production must stay allowed."
  }

  assert {
    condition     = length(local.assignments) == 2
    error_message = "both assignments must still be planned."
  }
}

run "explicit_exception_allows" {
  command = plan

  variables {
    production_restricted_permission_sets = []
    identity_groups = {
      "app-developers" = [{ permission_set = "Developer", accounts = ["workload_prod"] }]
    }
  }

  assert {
    condition     = length(local.restricted_production_assignments) == 0
    error_message = "an empty restricted list is the explicit, reviewable opt-out."
  }
}

run "explicit_production_account_keys_override_config" {
  command = plan

  variables {
    production_account_keys = ["workload_dev"]
    identity_groups = {
      "app-developers" = [{ permission_set = "Developer", accounts = ["workload_dev"] }]
    }
  }

  expect_failures = [terraform_data.production_assignment_guard]
}
