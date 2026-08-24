variable "project_id" {
  description = "Project ID where the snapshot-schedule resource policies will be created (6-30 characters, lowercase alphanumeric and hyphens)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be 6-30 characters, start with a lowercase letter, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "region" {
  description = "Region where the snapshot-schedule resource policies are created. Resource policies are regional and can only be attached to disks in the same region."
  type        = string
  default     = "europe-west1"
}

variable "labels" {
  description = "Labels applied to snapshots created by every schedule. Merged with each schedule's own snapshot_properties.labels."
  type        = map(string)
  default     = {}
}

variable "schedules" {
  description = <<-EOT
    Map of snapshot-schedule policies to create. The map key is the resource policy name.
    Each entry may specify at most one cadence (daily_schedule, weekly_schedule, or
    hourly_schedule); when none is given a secure default daily schedule (04:00, once per
    day) is applied. retention_policy and snapshot_properties fall back to secure defaults.
  EOT
  type = map(object({
    daily_schedule = optional(object({
      days_in_cycle = optional(number, 1)
      start_time    = optional(string, "04:00")
    }))
    weekly_schedule = optional(object({
      day_of_weeks = list(object({
        day        = string
        start_time = string
      }))
    }))
    hourly_schedule = optional(object({
      hours_in_cycle = number
      start_time     = string
    }))
    retention_policy = optional(object({
      max_retention_days    = optional(number, 30)
      on_source_disk_delete = optional(string, "KEEP_AUTO_SNAPSHOTS")
    }), {})
    snapshot_properties = optional(object({
      labels            = optional(map(string), {})
      storage_locations = optional(list(string))
      guest_flush       = optional(bool, false)
    }), {})
  }))

  default = {
    daily = {
      daily_schedule   = { start_time = "04:00", days_in_cycle = 1 }
      retention_policy = { max_retention_days = 30 }
    }
  }

  validation {
    condition     = alltrue([for name in keys(var.schedules) : can(regex("^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$", name))])
    error_message = "Every schedule name (map key) must be 1-63 characters, start with a lowercase letter, and contain only lowercase letters, digits, and hyphens."
  }

  validation {
    condition = alltrue([
      for s in values(var.schedules) :
      s.retention_policy.max_retention_days >= 1 && s.retention_policy.max_retention_days <= 3650
    ])
    error_message = "Every schedule retention_policy.max_retention_days must be between 1 and 3650 days."
  }

  validation {
    condition = alltrue([
      for s in values(var.schedules) :
      contains(["KEEP_AUTO_SNAPSHOTS", "APPLY_RETENTION_POLICY"], s.retention_policy.on_source_disk_delete)
    ])
    error_message = "Every schedule retention_policy.on_source_disk_delete must be one of: KEEP_AUTO_SNAPSHOTS, APPLY_RETENTION_POLICY."
  }

  validation {
    # All start_time values (across daily / weekly / hourly cadences) must be valid
    # 24-hour HH:MM strings.
    condition = alltrue([
      for t in flatten([
        for s in values(var.schedules) : concat(
          s.daily_schedule != null ? [s.daily_schedule.start_time] : [],
          s.hourly_schedule != null ? [s.hourly_schedule.start_time] : [],
          s.weekly_schedule != null ? [for d in s.weekly_schedule.day_of_weeks : d.start_time] : []
        )
      ]) : can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", t))
    ])
    error_message = "Every schedule start_time must be a valid 24-hour HH:MM value (e.g. '04:00')."
  }
}
