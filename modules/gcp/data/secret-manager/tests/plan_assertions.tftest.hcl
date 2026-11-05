# Resource-assertion tests for the secret-manager module.
# Proves containers, replication, optional versions, accessor IAM and the deletion
# guard are planned as expected under mock_provider.

mock_provider "google" {}

variables {
  project_id = "mock-project-id"

  secrets = {
    database-url = {
      labels = { app = "api" }
    }
    stripe-key = {
      replication = {
        user_managed_regions = ["europe-west1", "europe-west4"]
      }
    }
  }

  secret_accessors = {
    database-url = [
      "serviceAccount:a@mock-project-id.iam.gserviceaccount.com",
      "serviceAccount:b@mock-project-id.iam.gserviceaccount.com",
    ]
  }

  secret_values = {
    database-url = "postgres://example"
  }
}

run "secrets_plan_with_expected_shape" {
  command = plan

  assert {
    condition     = length(google_secret_manager_secret.this) == 2
    error_message = "one secret container must be planned per entry in var.secrets."
  }

  assert {
    condition     = google_secret_manager_secret.this["database-url"].secret_id == "database-url"
    error_message = "secret_id must match the map key."
  }

  assert {
    condition     = google_secret_manager_secret.this["database-url"].project == "mock-project-id"
    error_message = "secret must be planned in the supplied project."
  }

  # database-url defaults to automatic replication.
  assert {
    condition     = length(google_secret_manager_secret.this["database-url"].replication[0].auto) == 1
    error_message = "a secret with no user_managed_regions must use automatic replication."
  }

  # stripe-key uses user-managed replication across the supplied regions.
  assert {
    condition     = length(google_secret_manager_secret.this["stripe-key"].replication[0].user_managed) == 1
    error_message = "a secret with user_managed_regions must use user-managed replication."
  }

  assert {
    condition     = length(google_secret_manager_secret.this["stripe-key"].replication[0].user_managed[0].replicas) == 2
    error_message = "user-managed replication must create one replica per region."
  }

  # An initial version is created only for the secret present in secret_values.
  assert {
    condition     = length(google_secret_manager_secret_version.this) == 1
    error_message = "a version must be planned only for secrets present in secret_values."
  }

  # Two accessor members => two bindings, all with the secretAccessor role.
  assert {
    condition     = length(google_secret_manager_secret_iam_member.accessor) == 2
    error_message = "one IAM member binding must be planned per (secret, member) pair."
  }

  assert {
    condition     = alltrue([for b in google_secret_manager_secret_iam_member.accessor : b.role == "roles/secretmanager.secretAccessor"])
    error_message = "accessor bindings must grant only roles/secretmanager.secretAccessor."
  }

  # Deletion protection guard present by default.
  assert {
    condition     = length(terraform_data.deletion_protection_guard) == 1
    error_message = "the deletion-protection guard must be present when enabled (default)."
  }

  assert {
    condition     = output.secret_short_ids["database-url"] == "database-url"
    error_message = "secret_short_ids output must surface the short secret_id."
  }
}

run "no_versions_or_guard_when_disabled" {
  command = plan

  variables {
    secret_values              = {}
    enable_deletion_protection = false
  }

  assert {
    condition     = length(google_secret_manager_secret_version.this) == 0
    error_message = "no versions must be planned when secret_values is empty (containers only)."
  }

  assert {
    condition     = length(terraform_data.deletion_protection_guard) == 0
    error_message = "the deletion-protection guard must be absent when disabled."
  }
}
