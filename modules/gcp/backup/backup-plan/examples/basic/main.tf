# Example: two persistent-disk snapshot schedules for one region: a daily
# snapshot kept 30 days and a weekly snapshot kept a year. Snapshots stay in
# the same region as the disks (storage_locations), and the daily policy keeps
# applying retention after a source disk is deleted.
#
# Attach the policies to disks with google_compute_disk_resource_policy_attachment.
# Replace the placeholder project ID before use.
#
# Run `terraform init && terraform validate` here.

module "backup" {
  source = "../../"

  project_id = "my-project-id"
  region     = "europe-west2"

  labels = {
    managed-by = "terraform"
  }

  schedules = {
    daily-30d = {
      daily_schedule = { start_time = "04:00", days_in_cycle = 1 }
      retention_policy = {
        max_retention_days    = 30
        on_source_disk_delete = "APPLY_RETENTION_POLICY"
      }
      snapshot_properties = {
        storage_locations = ["europe-west2"]
      }
    }
    weekly-1y = {
      weekly_schedule = {
        day_of_weeks = [{ day = "SUNDAY", start_time = "02:00" }]
      }
      retention_policy = { max_retention_days = 365 }
      snapshot_properties = {
        storage_locations = ["europe-west2"]
      }
    }
  }
}
