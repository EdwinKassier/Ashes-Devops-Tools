# Regression test: the CDN module always creates an HTTPS proxy backed by a
# managed SSL certificate, so an empty domains list is invalid (it would yield
# an HTTPS proxy with no certificates, rejected at apply).
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id = "mock-project"
  lb_name    = "test-lb"
}

run "rejects_empty_domains" {
  command = plan

  variables {
    domains = []
  }

  expect_failures = [var.domains]
}

run "accepts_non_empty_domains" {
  command = plan

  variables {
    domains = ["example.com"]
  }
}
