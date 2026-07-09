# Regression test for budget_filter.projects formatting.
# The Budget API requires each entry in budget_filter.projects to be in
# projects/<id> form; bare project IDs are rejected/ignored.

mock_provider "google" {}

variables {
  billing_account      = "012345-6789AB-CDEF01"
  project_id           = "mock-project"
  project_name         = "mock-project"
  monthly_budget_limit = 500
  region               = "europe-west1"
  projects             = ["proj-a", "proj-b"]
}

run "budget_filter_projects_are_prefixed" {
  command = plan

  assert {
    condition = length(google_billing_budget.monthly_budget.budget_filter[0].projects) > 0 && alltrue([
      for p in google_billing_budget.monthly_budget.budget_filter[0].projects :
      startswith(p, "projects/")
    ])
    error_message = "budget_filter.projects entries must be in projects/<id> form and at least one must be planned"
  }
}
