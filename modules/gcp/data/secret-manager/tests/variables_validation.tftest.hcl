# Variable validation tests for the secret-manager module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id = "mock-project-id"
}

# ── var.project_id ────────────────────────────────────────────────────────────
run "valid_project_id_accepted" {
  command = plan
  variables { project_id = "my-project-id" }
}

run "invalid_project_id_rejected" {
  command         = plan
  expect_failures = [var.project_id]
  variables { project_id = "INVALID PROJECT!" }
}

# ── var.secrets name format ───────────────────────────────────────────────────
run "valid_secret_name_accepted" {
  command = plan
  variables {
    secrets = {
      database-url = {}
    }
  }
}

run "invalid_secret_name_rejected" {
  command         = plan
  expect_failures = [var.secrets]
  variables {
    secrets = {
      "bad name!" = {}
    }
  }
}

# ── var.secret_values must reference a declared secret ────────────────────────
run "secret_value_for_declared_secret_accepted" {
  command = plan
  variables {
    secrets       = { database-url = {} }
    secret_values = { database-url = "postgres://example" }
  }
}

run "secret_value_for_unknown_secret_rejected" {
  command         = plan
  expect_failures = [var.secret_values]
  variables {
    secrets       = { database-url = {} }
    secret_values = { does-not-exist = "oops" }
  }
}

# ── var.secret_accessors must reference a declared secret ─────────────────────
run "accessor_for_unknown_secret_rejected" {
  command         = plan
  expect_failures = [var.secret_accessors]
  variables {
    secrets          = { database-url = {} }
    secret_accessors = { does-not-exist = ["serviceAccount:a@mock-project-id.iam.gserviceaccount.com"] }
  }
}

# ── ephemeral_secret_values ───────────────────────────────────────────────────
run "ephemeral_value_for_flagged_secret_accepted" {
  command = plan

  variables {
    secrets                 = { api-token = { ephemeral_value = true } }
    ephemeral_secret_values = { api-token = "tok-123" }
  }
}

run "ephemeral_value_for_unflagged_secret_rejected" {
  command = plan

  expect_failures = [var.ephemeral_secret_values]

  variables {
    secrets                 = { api-token = {} }
    ephemeral_secret_values = { api-token = "tok-123" }
  }
}

run "flagged_secret_without_ephemeral_value_rejected" {
  command = plan

  expect_failures = [var.ephemeral_secret_values]

  variables {
    secrets = { api-token = { ephemeral_value = true } }
  }
}

run "flagged_secret_in_secret_values_rejected" {
  command = plan

  expect_failures = [var.secret_values]

  variables {
    secrets                 = { api-token = { ephemeral_value = true } }
    secret_values           = { api-token = "inline" }
    ephemeral_secret_values = { api-token = "tok-123" }
  }
}
