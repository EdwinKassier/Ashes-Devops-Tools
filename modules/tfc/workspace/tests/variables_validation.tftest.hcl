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
