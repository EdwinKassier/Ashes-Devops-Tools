# Variable validation tests for modules/supabase/project.
# No Supabase credentials required — validation blocks fire before resource evaluation.

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
  variables { organization_id = "abcdefghijklmnop" }
}

run "short_organization_id_rejected" {
  command         = plan
  expect_failures = [var.organization_id]
  variables { organization_id = "abc" }
}

run "uppercase_organization_id_rejected" {
  command         = plan
  expect_failures = [var.organization_id]
  variables { organization_id = "ABCDEFGHIJKLMNOP" }
}

# ── project_name ───────────────────────────────────────────────────────────────

run "valid_project_name_accepted" {
  command = plan
  variables { project_name = "my-app-qa" }
}

run "too_short_project_name_rejected" {
  command         = plan
  expect_failures = [var.project_name]
  variables { project_name = "ab" }
}

run "too_long_project_name_rejected" {
  command         = plan
  expect_failures = [var.project_name]
  variables { project_name = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" } # 65 chars
}

# ── database_password ──────────────────────────────────────────────────────────

run "valid_password_accepted" {
  command = plan
  variables { database_password = "exactly-sixteen!!" }
}

run "too_short_password_rejected" {
  command         = plan
  expect_failures = [var.database_password]
  variables { database_password = "short" }
}

# ── region ─────────────────────────────────────────────────────────────────────

run "valid_region_accepted" {
  command = plan
  variables { region = "us-east-1" }
}

run "invalid_region_rejected" {
  command         = plan
  expect_failures = [var.region]
  variables { region = "mars-west-1" }
}
