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
