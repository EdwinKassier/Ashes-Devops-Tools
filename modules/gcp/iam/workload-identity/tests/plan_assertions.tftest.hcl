# Plan assertions for the iam/workload-identity module: verify the WIF pool is planned
# with the caller-supplied id and display name.
# All runs use mock_provider so no GCP credentials are required.

mock_provider "google" {}

variables {
  project_id   = "mock-project"
  pool_id      = "test-pool"
  display_name = "Test Pool"
}

run "pool_wired" {
  command = plan

  assert {
    condition     = google_iam_workload_identity_pool.pool.workload_identity_pool_id == var.pool_id
    error_message = "WIF pool id must be the caller-supplied pool_id."
  }

  assert {
    condition     = google_iam_workload_identity_pool.pool.display_name == var.display_name
    error_message = "WIF pool display name must be the caller-supplied display_name."
  }

  assert {
    condition     = google_iam_workload_identity_pool.pool.project == var.project_id
    error_message = "WIF pool must be created in the caller-supplied project."
  }
}

# The GitLab trust matches the namespace or its sub-groups only, never a
# sibling group that merely shares the prefix ("acme" must not trust "acme-evil").
run "gitlab_namespace_is_not_a_prefix_match" {
  command = plan

  variables {
    enable_gitlab_provider = true
    gitlab_namespace       = "acme/"
  }

  assert {
    condition     = google_iam_workload_identity_pool_provider.gitlab[0].attribute_condition == "assertion.namespace_path == 'acme' || assertion.namespace_path.startsWith('acme/')"
    error_message = "GitLab attribute_condition must be namespace_path == X || startsWith(X/), not a bare prefix."
  }
}
