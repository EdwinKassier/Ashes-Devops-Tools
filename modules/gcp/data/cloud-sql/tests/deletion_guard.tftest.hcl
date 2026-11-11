# Deletion guard behaviour for the cloud-sql module. Runs apply against
# mock_provider (no GCP credentials) so later runs plan against real state.
#
# The guard carries prevent_destroy and replace_triggered_by on the instance id,
# so a plan that REPLACES a protected instance also plans to replace the guard
# and fails with "Instance cannot be destroyed". That failure is a plan error,
# not a checkable condition, so `terraform test` cannot expect it; the runs
# below cover the paths that must still succeed. To see the block, add
# `plan_options { replace = [google_sql_database_instance.this] }` to
# "protected_in_place_update_is_allowed": the run then fails on the guard.

mock_provider "google" {}

variables {
  project_id      = "mock-project"
  region          = "europe-west1"
  name            = "mock-db"
  private_network = "projects/mock-project/global/networks/hub"
}

run "protected_instance_is_created_with_guard" {
  command = apply

  assert {
    condition     = length(terraform_data.deletion_protection_guard) == 1
    error_message = "enable_deletion_protection (default true) must create the guard."
  }

  assert {
    condition     = google_sql_database_instance.this.deletion_protection == true
    error_message = "the instance's own deletion_protection must be set too."
  }
}

run "protected_in_place_update_is_allowed" {
  # Same state as the run above. An in-place change keeps the instance id, so
  # replace_triggered_by does not fire and the guard must not block the plan.
  command = plan

  variables {
    tier = "db-custom-2-7680"
  }

  assert {
    condition     = google_sql_database_instance.this.settings[0].tier == "db-custom-2-7680"
    error_message = "an in-place tier change on a protected instance must plan."
  }
}

run "unprotected_instance_is_created_without_guard" {
  state_key = "unprotected"
  command   = apply

  variables {
    enable_deletion_protection = false
  }

  assert {
    condition     = length(terraform_data.deletion_protection_guard) == 0
    error_message = "enable_deletion_protection = false must not create the guard."
  }
}

run "unprotected_instance_can_be_replaced" {
  state_key = "unprotected"
  command   = plan

  variables {
    enable_deletion_protection = false
  }

  plan_options {
    replace = [google_sql_database_instance.this]
  }

  assert {
    condition     = google_sql_database_instance.this.deletion_protection == false
    error_message = "an unprotected instance must plan a replacement without a guard error."
  }
}
