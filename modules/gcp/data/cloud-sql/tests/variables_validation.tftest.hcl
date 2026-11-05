# Variable validation tests for the cloud-sql module.
# All runs use mock_provider so no GCP credentials are required.
# Validation blocks fire before resource evaluation.

mock_provider "google" {}

variables {
  project_id      = "mock-project"
  region          = "europe-west1"
  name            = "mock-db"
  private_network = "projects/mock-project/global/networks/hub"
}

# ── project_id ─────────────────────────────────────────────────────────────────

run "rejects_invalid_project_id" {
  command = plan

  expect_failures = [var.project_id]

  variables {
    project_id = "INVALID PROJECT!"
  }
}

# ── region ─────────────────────────────────────────────────────────────────────

run "rejects_invalid_region" {
  command = plan

  expect_failures = [var.region]

  variables {
    region = "not a region"
  }
}

# ── name ───────────────────────────────────────────────────────────────────────

run "rejects_invalid_instance_name" {
  command = plan

  expect_failures = [var.name]

  variables {
    name = "Invalid_Name"
  }
}

# ── database_version (PostgreSQL only) ─────────────────────────────────────────

run "accepts_postgres_version" {
  command = plan

  variables {
    database_version = "POSTGRES_15"
  }
}

run "rejects_non_postgres_version" {
  command = plan

  expect_failures = [var.database_version]

  variables {
    database_version = "MYSQL_8_0"
  }
}

# ── tier ───────────────────────────────────────────────────────────────────────

run "rejects_invalid_tier" {
  command = plan

  expect_failures = [var.tier]

  variables {
    tier = "huge-machine"
  }
}

# ── backup_start_time ──────────────────────────────────────────────────────────

run "rejects_invalid_backup_start_time" {
  command = plan

  expect_failures = [var.backup_start_time]

  variables {
    backup_start_time = "25:00"
  }
}

# ── transaction_log_retention_days (boundaries) ────────────────────────────────

run "accepts_min_log_retention" {
  command = plan

  variables {
    transaction_log_retention_days = 1
  }
}

run "accepts_max_log_retention" {
  command = plan

  variables {
    transaction_log_retention_days = 35
  }
}

run "rejects_log_retention_above_max" {
  command = plan

  expect_failures = [var.transaction_log_retention_days]

  variables {
    transaction_log_retention_days = 36
  }
}

# ── maintenance_window_day / hour ──────────────────────────────────────────────

run "rejects_invalid_maintenance_day" {
  command = plan

  expect_failures = [var.maintenance_window_day]

  variables {
    maintenance_window_day = 8
  }
}

run "rejects_invalid_maintenance_hour" {
  command = plan

  expect_failures = [var.maintenance_window_hour]

  variables {
    maintenance_window_hour = 24
  }
}

# ── maintenance_window_update_track ────────────────────────────────────────────

run "rejects_invalid_update_track" {
  command = plan

  expect_failures = [var.maintenance_window_update_track]

  variables {
    maintenance_window_update_track = "nightly"
  }
}
