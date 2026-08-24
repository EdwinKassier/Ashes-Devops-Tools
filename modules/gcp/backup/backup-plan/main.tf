/**
 * Backup Plan Module - Scheduled Persistent Disk Snapshots
 *
 * GCP parity counterpart to the AWS backup modules (backup-vault + backup-org-policy).
 * Where AWS centralizes scheduled backups + retention in a WORM vault, GCP expresses
 * the same "scheduled backups with a retention policy" capability through
 * google_compute_resource_policy snapshot-schedule policies. Attach the resulting
 * policies to persistent disks to get automatic, retained snapshots.
 *
 * Each entry in var.schedules becomes one resource policy. A schedule may specify
 * exactly one of daily / weekly / hourly cadence; when none is given the module
 * falls back to a secure default daily schedule.
 */

locals {
  # Resolve the effective daily schedule per entry:
  #   - use the explicit daily_schedule when provided;
  #   - otherwise, when neither weekly nor hourly is set, apply the secure default
  #     daily cadence (once per day at 04:00);
  #   - when weekly or hourly is set, no daily block is emitted (null).
  effective_daily = {
    for name, s in var.schedules : name => (
      s.daily_schedule != null ? s.daily_schedule : (
        s.weekly_schedule == null && s.hourly_schedule == null
        ? { days_in_cycle = 1, start_time = "04:00" }
        : null
      )
    )
  }
}

resource "google_compute_resource_policy" "snapshot" {
  for_each = var.schedules

  name    = each.key
  project = var.project_id
  region  = var.region

  snapshot_schedule_policy {
    schedule {
      dynamic "daily_schedule" {
        for_each = local.effective_daily[each.key] != null ? [local.effective_daily[each.key]] : []
        content {
          days_in_cycle = daily_schedule.value.days_in_cycle
          start_time    = daily_schedule.value.start_time
        }
      }

      dynamic "weekly_schedule" {
        for_each = each.value.weekly_schedule != null ? [each.value.weekly_schedule] : []
        content {
          dynamic "day_of_weeks" {
            for_each = weekly_schedule.value.day_of_weeks
            content {
              day        = day_of_weeks.value.day
              start_time = day_of_weeks.value.start_time
            }
          }
        }
      }

      dynamic "hourly_schedule" {
        for_each = each.value.hourly_schedule != null ? [each.value.hourly_schedule] : []
        content {
          hours_in_cycle = hourly_schedule.value.hours_in_cycle
          start_time     = hourly_schedule.value.start_time
        }
      }
    }

    retention_policy {
      max_retention_days    = each.value.retention_policy.max_retention_days
      on_source_disk_delete = each.value.retention_policy.on_source_disk_delete
    }

    snapshot_properties {
      labels            = merge(var.labels, each.value.snapshot_properties.labels)
      guest_flush       = each.value.snapshot_properties.guest_flush
      storage_locations = each.value.snapshot_properties.storage_locations
    }
  }
}
