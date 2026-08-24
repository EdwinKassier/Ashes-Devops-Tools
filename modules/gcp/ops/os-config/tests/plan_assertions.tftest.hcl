# Plan assertions for the ops/os-config module (mock_provider — no creds).

mock_provider "google" {}

variables {
  project_id = "my-project"
}

run "creates_patch_deployment_per_entry" {
  command = plan

  variables {
    patch_deployments = {
      weekly-all = {
        all_instances = true
        reboot_config = "DEFAULT"
        day_of_week   = "SUNDAY"
        start_time    = "03:00"
        time_zone     = "Europe/London"
      }
      db-tier = {
        all_instances   = false
        instance_labels = { tier = "database" }
        reboot_config   = "NEVER"
        day_of_week     = "SATURDAY"
        start_time      = "02:30"
      }
    }
  }

  assert {
    condition     = length(google_os_config_patch_deployment.this) == 2
    error_message = "one patch deployment must be planned per entry"
  }

  assert {
    condition     = google_os_config_patch_deployment.this["weekly-all"].patch_deployment_id == "weekly-all"
    error_message = "patch_deployment_id must be the map key"
  }

  assert {
    condition     = google_os_config_patch_deployment.this["weekly-all"].instance_filter[0].all == true
    error_message = "all_instances = true must set instance_filter.all"
  }

  assert {
    condition     = google_os_config_patch_deployment.this["weekly-all"].patch_config[0].reboot_config == "DEFAULT"
    error_message = "reboot_config must propagate"
  }

  assert {
    condition     = google_os_config_patch_deployment.this["db-tier"].recurring_schedule[0].weekly[0].day_of_week == "SATURDAY"
    error_message = "weekly day_of_week must propagate"
  }

  assert {
    condition     = google_os_config_patch_deployment.this["db-tier"].recurring_schedule[0].time_of_day[0].hours == 2
    error_message = "start_time hours must be parsed into time_of_day"
  }
}
