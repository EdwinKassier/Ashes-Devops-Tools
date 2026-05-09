# Variable validation tests for modules/supabase/environment.
# Uses override_module to bypass child module evaluation (data source
# postconditions would fail with empty mock results).

mock_provider "supabase" {}

variables {
  organization_id   = "abcdefghijklmnop"
  project_name      = "my-app-qa"
  database_password = "exactly-sixteen!!"
  region            = "eu-west-2"
}

# ── organization_id ────────────────────────────────────────────────────────────

run "valid_organization_id_accepted" {
  command = plan

  override_module {
    target  = module.project
    outputs = { id = "abcdefghijklmnopqrst", name = "my-app-qa", database_password = "exactly-sixteen!!" }
  }
  override_module {
    target  = module.settings
    outputs = { project_ref = "abcdefghijklmnopqrst" }
  }

  variables { organization_id = "abcdefghijklmnop" }
}

run "short_organization_id_rejected" {
  command = plan
  expect_failures = [var.organization_id]
  variables { organization_id = "abc" }
}

# ── jwt_expiry ─────────────────────────────────────────────────────────────────

run "min_jwt_expiry_accepted" {
  command = plan

  override_module {
    target  = module.project
    outputs = { id = "abcdefghijklmnopqrst", name = "my-app-qa", database_password = "exactly-sixteen!!" }
  }
  override_module {
    target  = module.settings
    outputs = { project_ref = "abcdefghijklmnopqrst" }
  }

  variables { jwt_expiry = 300 }
}

run "below_min_jwt_expiry_rejected" {
  command = plan
  expect_failures = [var.jwt_expiry]
  variables { jwt_expiry = 299 }
}

run "invalid_region_rejected" {
  command = plan
  expect_failures = [var.region]
  variables { region = "mars-west-1" }
}
