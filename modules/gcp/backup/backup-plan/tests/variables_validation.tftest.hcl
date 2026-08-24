# Variable validation tests for the backup-plan module (mock_provider — no creds).

mock_provider "google" {}

variables {
  project_id = "my-project"
  region     = "europe-west1"
}

run "accepts_defaults" {
  command = plan
}

run "rejects_bad_retention_days" {
  command = plan

  expect_failures = [var.schedules]

  variables {
    schedules = {
      bad = { retention_policy = { max_retention_days = 5000 } }
    }
  }
}

run "rejects_zero_retention_days" {
  command = plan

  expect_failures = [var.schedules]

  variables {
    schedules = {
      bad = { retention_policy = { max_retention_days = 0 } }
    }
  }
}

run "rejects_bad_on_source_disk_delete" {
  command = plan

  expect_failures = [var.schedules]

  variables {
    schedules = {
      bad = { retention_policy = { max_retention_days = 30, on_source_disk_delete = "WIPE" } }
    }
  }
}

run "rejects_bad_start_time" {
  command = plan

  expect_failures = [var.schedules]

  variables {
    schedules = {
      bad = { daily_schedule = { start_time = "25:99" } }
    }
  }
}

run "rejects_bad_schedule_name" {
  command = plan

  expect_failures = [var.schedules]

  variables {
    schedules = {
      "Bad_Name" = { retention_policy = { max_retention_days = 30 } }
    }
  }
}
