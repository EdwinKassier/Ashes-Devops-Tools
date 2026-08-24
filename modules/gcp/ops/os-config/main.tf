# VM Manager (OS Config) scheduled patch deployments — the GCP parity counterpart
# to AWS Systems Manager patch baselines / Maintenance Windows. Each entry is a
# recurring weekly OS patch job against the matched Compute Engine instances.

locals {
  # Split "HH:MM" into integer hours/minutes for the schedule time_of_day block.
  parts = { for k, d in var.patch_deployments : k => {
    hours   = tonumber(split(":", d.start_time)[0])
    minutes = tonumber(split(":", d.start_time)[1])
  } }
}

resource "google_os_config_patch_deployment" "this" {
  for_each = var.patch_deployments

  project             = var.project_id
  patch_deployment_id = each.key
  description         = each.value.description

  instance_filter {
    all = each.value.all_instances

    dynamic "group_labels" {
      for_each = each.value.all_instances ? [] : (length(each.value.instance_labels) > 0 ? [each.value.instance_labels] : [])
      content {
        labels = group_labels.value
      }
    }
  }

  patch_config {
    reboot_config = each.value.reboot_config
  }

  recurring_schedule {
    time_zone {
      id = each.value.time_zone
    }

    time_of_day {
      hours   = local.parts[each.key].hours
      minutes = local.parts[each.key].minutes
      seconds = 0
      nanos   = 0
    }

    weekly {
      day_of_week = each.value.day_of_week
    }
  }
}
