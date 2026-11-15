# Key allowlists of the untyped (type = any) inputs of this root or module. The
# variable validations reject any key outside these lists. Each list must equal
# the attributes of the typed object the value is forwarded to: an extra key
# would be dropped silently by type conversion, and a missing key could not be
# set. scripts/check-any-allowlists.py (make consistency) compares every list
# with the stage type named in scripts/any-allowlists.json.
locals {
  allowed_keys = {
    # modules/gcp/stages/net-spoke additional_regions
    additional_regions = {
      self             = ["subnet_cidrs", "secondary_ranges", "nat"]
      subnet_cidrs     = ["public", "private", "database"]
      secondary_ranges = ["range_name", "ip_cidr_range"]
    }
    # modules/gcp/backup/backup-plan schedules
    vm_backup_schedules = {
      self                = ["daily_schedule", "weekly_schedule", "hourly_schedule", "retention_policy", "snapshot_properties"]
      daily_schedule      = ["days_in_cycle", "start_time"]
      weekly_schedule     = ["day_of_weeks"]
      hourly_schedule     = ["hours_in_cycle", "start_time"]
      retention_policy    = ["max_retention_days", "on_source_disk_delete"]
      snapshot_properties = ["labels", "storage_locations", "guest_flush"]
    }
    # modules/gcp/ops/os-config patch_deployments
    os_patch_deployments = {
      self = ["all_instances", "instance_labels", "reboot_config", "day_of_week", "start_time", "time_zone", "description"]
    }
  }
}
