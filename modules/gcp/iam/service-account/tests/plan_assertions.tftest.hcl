# Plan assertions for the iam/service-account module (mock_provider, no credentials).

mock_provider "google" {}

variables {
  project_id   = "mock-project"
  account_id   = "my-service-account"
  display_name = "My Service Account"
}

# A time-boxed impersonation grant carries a request.time expiry condition.
run "impersonation_can_be_time_boxed" {
  command = plan

  variables {
    impersonation_members    = ["user:admin@example.com"]
    impersonation_expires_at = "2026-12-31T00:00:00Z"
  }

  assert {
    condition     = google_service_account_iam_member.impersonation["user:admin@example.com"].condition[0].expression == "request.time < timestamp(\"2026-12-31T00:00:00Z\")"
    error_message = "impersonation_expires_at must add a request.time < timestamp(...) condition."
  }
}
