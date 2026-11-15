# Plan assertions for the backup-vault module (mock_provider, no credentials).

mock_provider "google" {}

variables {
  project_id              = "acme-prod-host"
  location                = "europe-west2"
  vault_id                = "prod-vault"
  enforced_retention_days = 35
  cloud_sql_instances     = { orders = "projects/acme-prod-svc/instances/orders-db" }
  cloud_sql_source_projects = {
    payments = "acme-prod-svc"
  }
}

run "vault_and_plan" {
  command = plan

  assert {
    condition = (
      google_backup_dr_backup_vault.this.backup_minimum_enforced_retention_duration == "3024000s" &&
      google_backup_dr_backup_vault.this.access_restriction == "WITHIN_ORGANIZATION" &&
      google_backup_dr_backup_vault.this.location == "europe-west2"
    )
    error_message = "the vault must enforce 35 days of retention, stay inside the organization and sit in the given region."
  }

  assert {
    condition = (
      google_backup_dr_backup_plan.cloud_sql[0].resource_type == "sqladmin.googleapis.com/Instance" &&
      google_backup_dr_backup_plan.cloud_sql[0].location == "europe-west2" &&
      google_backup_dr_backup_plan.cloud_sql[0].backup_rules[0].backup_retention_days == 35 &&
      google_backup_dr_backup_plan.cloud_sql[0].backup_rules[0].standard_schedule[0].recurrence_type == "DAILY"
    )
    error_message = "Cloud SQL must get a daily plan, in the vault region, at the enforced retention."
  }

  assert {
    condition = (
      google_backup_dr_backup_plan_association.cloud_sql["orders"].resource == "projects/acme-prod-svc/instances/orders-db" &&
      google_backup_dr_backup_plan_association.cloud_sql["orders"].resource_type == "sqladmin.googleapis.com/Instance"
    )
    error_message = "every listed Cloud SQL instance must be associated with the plan."
  }

  assert {
    condition     = google_backup_dr_backup_vault.this.effective_time == null
    error_message = "the module must never lock the enforced retention unless lock_effective_time is set."
  }

  assert {
    condition = (
      google_project_iam_member.cloud_sql_operator["payments"].project == "acme-prod-svc" &&
      google_project_iam_member.cloud_sql_operator["payments"].role == "roles/backupdr.cloudSqlOperator"
    )
    error_message = "the vault service agent must get roles/backupdr.cloudSqlOperator in each Cloud SQL project outside the vault project."
  }

  assert {
    condition     = toset(keys(google_project_service.backupdr)) == toset(["vault", "payments"])
    error_message = "the Backup and DR API must be on in the vault project and in every Cloud SQL source project."
  }
}

# A vault with nothing to protect: no plan, no association, no grant.
run "vault_only" {
  command = plan

  variables {
    cloud_sql_instances       = {}
    cloud_sql_source_projects = {}
  }

  assert {
    condition = (
      length(google_backup_dr_backup_plan.cloud_sql) == 0 &&
      length(google_backup_dr_backup_plan_association.cloud_sql) == 0 &&
      length(google_project_iam_member.cloud_sql_operator) == 0
    )
    error_message = "with no Cloud SQL instance the module must create only the vault."
  }
}

# The lock is the owner's explicit, irreversible choice.
run "lock_only_when_asked" {
  command = plan

  variables {
    lock_effective_time = "2027-01-01T00:00:00Z"
  }

  assert {
    condition     = google_backup_dr_backup_vault.this.effective_time == "2027-01-01T00:00:00Z"
    error_message = "lock_effective_time must set the vault's effective_time."
  }
}
