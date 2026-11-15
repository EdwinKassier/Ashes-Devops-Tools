# Input validation for the backup-vault module (mock_provider, no credentials).

mock_provider "google" {}

variables {
  project_id = "acme-prod-host"
  location   = "europe-west2"
  vault_id   = "prod-vault"
}

run "accepts_defaults" {
  command = plan
}

run "rejects_short_retention" {
  command = plan

  variables {
    enforced_retention_days = 0
  }

  expect_failures = [var.enforced_retention_days]
}

# Cloud SQL accepts a vault with at most 10 years (3,653 days) of enforced retention.
run "rejects_retention_above_cloud_sql_limit" {
  command = plan

  variables {
    enforced_retention_days = 3654
  }

  expect_failures = [var.enforced_retention_days]
}

run "rejects_fractional_retention" {
  command = plan

  variables {
    enforced_retention_days = 1.5
  }

  expect_failures = [var.enforced_retention_days]
}

run "rejects_bad_instance_name" {
  command = plan

  variables {
    cloud_sql_instances = { bad = "orders-db" }
  }

  expect_failures = [var.cloud_sql_instances]
}

run "rejects_bad_source_project" {
  command = plan

  variables {
    cloud_sql_source_projects = { team = "Not A Project" }
  }

  expect_failures = [var.cloud_sql_source_projects]
}

run "rejects_multi_region_location" {
  command = plan

  variables {
    location = "eu"
  }

  expect_failures = [var.location]
}

run "rejects_bad_vault_id" {
  command = plan

  variables {
    vault_id = "Prod_Vault"
  }

  expect_failures = [var.vault_id]
}

run "rejects_bad_project_id" {
  command = plan

  variables {
    project_id = "x"
  }

  expect_failures = [var.project_id]
}

run "rejects_bad_lock_time" {
  command = plan

  variables {
    lock_effective_time = "next year"
  }

  expect_failures = [var.lock_effective_time]
}
