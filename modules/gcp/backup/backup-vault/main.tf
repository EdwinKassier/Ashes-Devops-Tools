/**
 * Backup Vault Module - Backup and DR Service vault for Cloud SQL
 *
 * The GCP counterpart of the AWS locked copy vault. A Backup and DR backup
 * vault keeps every backup immutable for enforced_retention_days and, with
 * access_restriction WITHIN_ORGANIZATION, accepts backup and restore only
 * inside the organization. A daily backup plan protects the listed Cloud SQL
 * instances (Cloud SQL "enhanced backups").
 *
 * The vault, its plan and the Cloud SQL instances share one region: Backup and
 * DR needs the plan in the instance region, and one region keeps the backups
 * inside gcp.resourceLocations.
 *
 * Irreversible: lock_effective_time locks the minimum enforced retention.
 * After that time nobody, not even a project owner, can lower it. The module
 * sets no lock unless lock_effective_time is given.
 */

locals {
  # The vault project plus every Cloud SQL project outside it. Static keys.
  api_projects = merge({ vault = var.project_id }, var.cloud_sql_source_projects)
}

resource "google_project_service" "backupdr" {
  for_each = local.api_projects

  project            = each.value
  service            = "backupdr.googleapis.com"
  disable_on_destroy = false
}

resource "google_backup_dr_backup_vault" "this" {
  project                                    = var.project_id
  location                                   = var.location
  backup_vault_id                            = var.vault_id
  description                                = "Landing-zone backup vault (enforced retention ${var.enforced_retention_days} days)."
  backup_minimum_enforced_retention_duration = "${var.enforced_retention_days * 86400}s"
  access_restriction                         = "WITHIN_ORGANIZATION"
  effective_time                             = var.lock_effective_time
  labels                                     = var.labels

  depends_on = [google_project_service.backupdr]
}

# The vault's service agent backs up Cloud SQL instances in other projects with
# roles/backupdr.cloudSqlOperator there. In the vault project it needs no grant.
resource "google_project_iam_member" "cloud_sql_operator" {
  for_each = var.cloud_sql_source_projects

  project = each.value
  role    = "roles/backupdr.cloudSqlOperator"
  member  = "serviceAccount:${google_backup_dr_backup_vault.this.service_account}"
}

resource "google_backup_dr_backup_plan" "cloud_sql" {
  count = length(var.cloud_sql_instances) > 0 ? 1 : 0

  project        = var.project_id
  location       = var.location
  backup_plan_id = "${var.vault_id}-cloudsql"
  description    = "Daily Cloud SQL backups kept ${var.enforced_retention_days} days."
  resource_type  = "sqladmin.googleapis.com/Instance"
  backup_vault   = google_backup_dr_backup_vault.this.id
  labels         = var.labels

  backup_rules {
    rule_id = "daily"
    # Equal to the vault minimum: the API refuses a shorter rule.
    backup_retention_days = var.enforced_retention_days

    standard_schedule {
      recurrence_type = "DAILY"
      time_zone       = "UTC"

      backup_window {
        start_hour_of_day = var.backup_window_start_hour
        end_hour_of_day   = var.backup_window_start_hour + 4
      }
    }
  }
}

resource "google_backup_dr_backup_plan_association" "cloud_sql" {
  for_each = var.cloud_sql_instances

  project                    = var.project_id
  location                   = var.location
  backup_plan_association_id = "${var.vault_id}-${each.key}"
  resource                   = each.value
  resource_type              = "sqladmin.googleapis.com/Instance"
  backup_plan                = google_backup_dr_backup_plan.cloud_sql[0].name

  depends_on = [google_project_iam_member.cloud_sql_operator]
}
