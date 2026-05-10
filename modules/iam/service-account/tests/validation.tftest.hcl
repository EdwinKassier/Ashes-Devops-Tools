mock_provider "google" {}

# A minimal valid service account plans without error.
run "valid_service_account" {
  variables {
    project_id   = "my-project"
    account_id   = "my-service-acct"
    display_name = "My Service Account"
  }

  command = plan

  assert {
    condition     = google_service_account.service_account.account_id == "my-service-acct"
    error_message = "Expected account_id to match input"
  }
}

# account_id that is too short (fewer than 6 chars) is rejected.
run "account_id_too_short" {
  variables {
    project_id   = "my-project"
    account_id   = "abc"
    display_name = "Too Short"
  }

  command = plan

  expect_failures = [var.account_id]
}

# account_id starting with a digit is rejected.
run "account_id_starts_with_digit" {
  variables {
    project_id   = "my-project"
    account_id   = "1invalid-sa"
    display_name = "Starts With Digit"
  }

  command = plan

  expect_failures = [var.account_id]
}

# project_roles with invalid format (missing roles/ prefix) is rejected.
run "invalid_project_role_format" {
  variables {
    project_id    = "my-project"
    account_id    = "my-service-acct"
    display_name  = "SA"
    project_roles = ["storage.admin"]
  }

  command = plan

  expect_failures = [var.project_roles]
}

# impersonation_members with invalid format (missing prefix) is rejected.
run "invalid_impersonation_member_format" {
  variables {
    project_id            = "my-project"
    account_id            = "my-service-acct"
    display_name          = "SA"
    impersonation_members = ["alice@example.com"]
  }

  command = plan

  expect_failures = [var.impersonation_members]
}

# Valid impersonation_members with correct prefix format are accepted.
run "valid_impersonation_members" {
  variables {
    project_id   = "my-project"
    account_id   = "my-service-acct"
    display_name = "SA"
    impersonation_members = [
      "user:alice@example.com",
      "group:devs@example.com",
      "serviceAccount:ci@my-project.iam.gserviceaccount.com",
    ]
  }

  command = plan

  assert {
    condition     = length(google_service_account_iam_member.impersonation) == 3
    error_message = "Expected 3 impersonation IAM members to be planned"
  }
}

# Valid project_roles with the roles/ prefix are accepted.
run "valid_project_roles" {
  variables {
    project_id   = "my-project"
    account_id   = "my-service-acct"
    display_name = "SA"
    project_roles = [
      "roles/storage.objectViewer",
      "roles/bigquery.dataViewer",
    ]
  }

  command = plan

  assert {
    condition     = length(google_project_iam_member.sa_project_roles) == 2
    error_message = "Expected 2 project IAM role bindings to be planned"
  }
}
