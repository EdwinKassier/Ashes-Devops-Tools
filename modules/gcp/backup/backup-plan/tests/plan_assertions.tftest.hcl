# Plan assertions for the backup-plan module (mock_provider — no creds).

mock_provider "google" {}

variables {
  project_id = "my-project"
  region     = "europe-west1"
}

# One resource policy is planned per schedule, in the configured region.
run "creates_policy_per_schedule" {
  command = plan

  variables {
    schedules = {
      daily-30d = {
        daily_schedule   = { start_time = "04:00", days_in_cycle = 1 }
        retention_policy = { max_retention_days = 30, on_source_disk_delete = "APPLY_RETENTION_POLICY" }
      }
      weekly-1y = {
        weekly_schedule  = { day_of_weeks = [{ day = "SUNDAY", start_time = "02:00" }] }
        retention_policy = { max_retention_days = 365 }
      }
    }
  }

  assert {
    condition     = length(google_compute_resource_policy.snapshot) == 2
    error_message = "Expected one resource policy per schedule"
  }

  assert {
    condition     = google_compute_resource_policy.snapshot["daily-30d"].region == "europe-west1"
    error_message = "Resource policy must be created in the configured region"
  }

  assert {
    condition     = google_compute_resource_policy.snapshot["daily-30d"].snapshot_schedule_policy[0].retention_policy[0].max_retention_days == 30
    error_message = "Retention max_retention_days must propagate from input"
  }

  assert {
    condition     = google_compute_resource_policy.snapshot["daily-30d"].snapshot_schedule_policy[0].retention_policy[0].on_source_disk_delete == "APPLY_RETENTION_POLICY"
    error_message = "on_source_disk_delete must propagate from input"
  }
}

# The default schedule set yields a daily policy with the secure default retention.
run "default_schedule" {
  command = plan

  assert {
    condition     = length(google_compute_resource_policy.snapshot) == 1
    error_message = "Default schedules should create exactly one daily policy"
  }
}
