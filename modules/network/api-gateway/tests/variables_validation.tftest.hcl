# Variable validation tests for the network/api_gateway module.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  project_id            = "mock-project"
  service_account_email = "sa@mock-project.iam.gserviceaccount.com"
}

# ── api_id ─────────────────────────────────────────────────────────────────────

run "accepts_valid_api_id" {
  command = plan

  variables {
    api_id = "my-api-v1"
  }
}

run "accepts_api_id_with_numbers" {
  command = plan

  variables {
    api_id = "payments-api-01"
  }
}

run "rejects_api_id_starting_with_number" {
  command = plan

  expect_failures = [var.api_id]

  variables {
    api_id = "1st-api"
  }
}

run "rejects_api_id_with_uppercase" {
  command = plan

  expect_failures = [var.api_id]

  variables {
    api_id = "MyAPI"
  }
}

run "rejects_api_id_too_short" {
  command = plan

  expect_failures = [var.api_id]

  variables {
    api_id = "ab"
  }
}

# ── gateway_id ─────────────────────────────────────────────────────────────────

run "accepts_valid_gateway_id" {
  command = plan

  variables {
    gateway_id = "prod-gateway"
  }
}

run "rejects_gateway_id_starting_with_number" {
  command = plan

  expect_failures = [var.gateway_id]

  variables {
    gateway_id = "1st-gateway"
  }
}

run "rejects_gateway_id_with_uppercase" {
  command = plan

  expect_failures = [var.gateway_id]

  variables {
    gateway_id = "ProdGateway"
  }
}
