/**
 * Copyright 2023 Ashes
 *
 * Cloud SQL (PostgreSQL) Module - Main Configuration
 *
 * Creates a managed PostgreSQL instance that is private by default: no public IP,
 * peered into a Shared VPC over Private Service Access, TLS-only, with automated
 * backups + point-in-time recovery, IAM database authentication, optional CMEK,
 * and deletion protection. Every control is a toggle so admins can compose the
 * posture they need.
 */

locals {
  # IAM database authentication is expressed as a database flag. It is managed here
  # (not via var.database_flags) so callers cannot accidentally duplicate it.
  iam_auth_flag = var.enable_iam_authentication ? [{
    name  = "cloudsql.iam_authentication"
    value = "on"
  }] : []

  all_database_flags = concat(local.iam_auth_flag, var.database_flags)

  # Keyed view of users so the for_each key set can be made non-sensitive while the
  # password it may carry stays sensitive.
  users_by_name = { for u in var.users : u.name => u }
}

# Deletion protection guard — present only when enable_deletion_protection = true.
# Terraform's prevent_destroy must be a static literal; it cannot reference a variable.
# This guard carries prevent_destroy = true and is created conditionally so that
# removing it (by toggling the flag) is also blocked, forcing an explicit state rm.
resource "terraform_data" "deletion_protection_guard" {
  count = var.enable_deletion_protection ? 1 : 0

  input = var.name

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_sql_database_instance" "this" {
  name             = var.name
  project          = var.project_id
  region           = var.region
  database_version = var.database_version

  deletion_protection = var.enable_deletion_protection

  # Optional customer-managed encryption key (CMEK); null uses Google-managed keys.
  encryption_key_name = var.encryption_key_name

  settings {
    tier              = var.tier
    availability_type = var.enable_high_availability ? "REGIONAL" : "ZONAL"
    disk_autoresize   = true
    user_labels       = var.labels

    # Private IP only — no public IPv4 — and reject any non-TLS connection.
    ip_configuration {
      ipv4_enabled    = false
      private_network = var.private_network
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = var.enable_point_in_time_recovery
      start_time                     = var.backup_start_time
      transaction_log_retention_days = var.transaction_log_retention_days
    }

    dynamic "database_flags" {
      for_each = local.all_database_flags
      content {
        name  = database_flags.value.name
        value = database_flags.value.value
      }
    }

    maintenance_window {
      day          = var.maintenance_window_day
      hour         = var.maintenance_window_hour
      update_track = var.maintenance_window_update_track
    }
  }
}

resource "google_sql_database" "this" {
  for_each = toset(var.databases)

  name     = each.value
  instance = google_sql_database_instance.this.name
  project  = var.project_id
}

resource "google_sql_user" "this" {
  # for_each over the user names only: nonsensitive() keeps the key set usable while
  # the password (looked up below) remains a sensitive value.
  for_each = nonsensitive(toset([for u in var.users : u.name]))

  name     = each.value
  instance = google_sql_database_instance.this.name
  project  = var.project_id
  type     = local.users_by_name[each.value].type

  # Built-in users authenticate with a password; IAM users must not carry one.
  password = local.users_by_name[each.value].type == "BUILT_IN" ? local.users_by_name[each.value].password : null
}
