mock_provider "tfe" {}

variables {
  name              = "gcp-organization"
  organization      = "acme"
  working_directory = "envs/gcp/organization"
}

run "rejects_invalid_name" {
  command = plan
  variables {
    name = "bad name with spaces"
  }
  expect_failures = [var.name]
}

run "rejects_invalid_execution_mode" {
  command = plan
  variables {
    execution_mode = "cloud"
  }
  expect_failures = [var.execution_mode]
}

run "rejects_invalid_variable_category" {
  command = plan
  variables {
    variables = {
      FOO = { value = "bar", category = "secret" }
    }
  }
  expect_failures = [var.variables]
}

run "accepts_valid_inputs" {
  command = plan
}

run "rejects_bad_notification_destination" {
  command = plan
  variables {
    notifications = {
      bad = { destination_type = "carrier-pigeon", url = "https://x" }
    }
  }
  expect_failures = [var.notifications]
}

run "rejects_non_email_without_url" {
  command = plan
  variables {
    notifications = {
      webhook = { destination_type = "generic" }
    }
  }
  expect_failures = [var.notifications]
}

run "rejects_vcs_repo_without_credential" {
  command = plan
  variables {
    vcs_repo = { identifier = "acme/repo" }
  }
  expect_failures = [var.vcs_repo]
}

run "accepts_vcs_repo_with_github_app" {
  command = plan
  variables {
    vcs_repo = { identifier = "acme/repo", github_app_installation_id = "ghain-abc" }
  }
}

run "assessment_triggers_accepted" {
  command = plan
  variables {
    notifications = {
      a = { destination_type = "email", email_user_ids = ["user-1"], triggers = ["assessment:drifted", "assessment:check_failure", "assessment:failed"] }
    }
  }
}

run "rejects_unknown_assessment_trigger" {
  command = plan
  variables {
    notifications = {
      a = { destination_type = "email", email_user_ids = ["user-1"], triggers = ["assessment:bogus"] }
    }
  }
  expect_failures = [var.notifications]
}
