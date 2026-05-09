# Variable validation tests for modules/supabase/settings.

mock_provider "supabase" {}

variables {
  project_ref = "abcdefghijklmnopqrst"
}

# ── project_ref ────────────────────────────────────────────────────────────────

run "valid_project_ref_accepted" {
  command = plan
  variables { project_ref = "abcdefghijklmnopqrst" }
}

run "short_project_ref_rejected" {
  command = plan
  expect_failures = [var.project_ref]
  variables { project_ref = "tooshort" }
}

run "uppercase_project_ref_rejected" {
  command = plan
  expect_failures = [var.project_ref]
  variables { project_ref = "ABCDEFGHIJKLMNOPQRST" }
}

# ── api_max_rows ───────────────────────────────────────────────────────────────

run "min_api_max_rows_accepted" {
  command = plan
  variables { api_max_rows = 100 }
}

run "max_api_max_rows_accepted" {
  command = plan
  variables { api_max_rows = 100000 }
}

run "below_min_api_max_rows_rejected" {
  command = plan
  expect_failures = [var.api_max_rows]
  variables { api_max_rows = 99 }
}

run "above_max_api_max_rows_rejected" {
  command = plan
  expect_failures = [var.api_max_rows]
  variables { api_max_rows = 100001 }
}

# ── jwt_expiry ─────────────────────────────────────────────────────────────────

run "min_jwt_expiry_accepted" {
  command = plan
  variables { jwt_expiry = 300 }
}

run "max_jwt_expiry_accepted" {
  command = plan
  variables { jwt_expiry = 604800 }
}

run "below_min_jwt_expiry_rejected" {
  command = plan
  expect_failures = [var.jwt_expiry]
  variables { jwt_expiry = 299 }
}

run "above_max_jwt_expiry_rejected" {
  command = plan
  expect_failures = [var.jwt_expiry]
  variables { jwt_expiry = 604801 }
}

# ── password_min_length ────────────────────────────────────────────────────────

run "min_password_length_accepted" {
  command = plan
  variables { password_min_length = 6 }
}

run "max_password_length_accepted" {
  command = plan
  variables { password_min_length = 100 }
}

run "below_min_password_length_rejected" {
  command = plan
  expect_failures = [var.password_min_length]
  variables { password_min_length = 5 }
}
