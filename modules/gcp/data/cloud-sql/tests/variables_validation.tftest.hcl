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

run "enterprise_plus_requires_perf_optimized_tier" {
  command = plan

  variables {
    edition = "ENTERPRISE_PLUS"
    tier    = "db-custom-1-3840"
  }

  expect_failures = [var.edition]
}

# ── users / user_passwords (ephemeral passwords) ──────────────────────────────

run "accepts_ephemeral_password_user" {
  command = plan

  variables {
    users          = [{ name = "app", ephemeral_password = true }]
    user_passwords = { app = "s3cret-value" }
  }
}

run "rejects_ephemeral_password_user_with_inline_password" {
  command = plan

  expect_failures = [var.users]

  variables {
    users          = [{ name = "app", password = "inline", ephemeral_password = true }]
    user_passwords = { app = "s3cret-value" }
  }
}

run "rejects_ephemeral_password_on_iam_user" {
  command = plan

  expect_failures = [var.users]

  variables {
    users          = [{ name = "svc@mock-project.iam", type = "CLOUD_IAM_SERVICE_ACCOUNT", ephemeral_password = true }]
    user_passwords = { "svc@mock-project.iam" = "x" }
  }
}

run "rejects_user_password_for_undeclared_user" {
  command = plan

  expect_failures = [var.user_passwords]

  variables {
    users          = [{ name = "app", password = "inline" }]
    user_passwords = { app = "s3cret-value" }
  }
}

run "rejects_ephemeral_password_user_without_entry" {
  command = plan

  expect_failures = [var.user_passwords]

  variables {
    users = [{ name = "app", ephemeral_password = true }]
  }
}

run "rejects_invalid_backup_location" {
  command = plan

  expect_failures = [var.backup_location]

  variables {
    backup_location = "Europe West 2"
  }
}
