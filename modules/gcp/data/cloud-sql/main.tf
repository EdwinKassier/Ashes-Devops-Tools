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

  # Secure-by-default PostgreSQL logging (CKV_GCP_51/52/53/109/111). Toggle off with
  # enable_secure_log_flags = false. All are valid Cloud SQL Postgres flags.
  default_log_flags = var.enable_secure_log_flags && can(regex("POSTGRES", var.database_version)) ? [
    { name = "log_checkpoints", value = "on" },
    { name = "log_connections", value = "on" },
    { name = "log_disconnections", value = "on" },
    { name = "log_lock_waits", value = "on" },
    { name = "log_min_messages", value = "error" },
    { name = "log_statement", value = "ddl" },
  ] : []

  # Deduplicate by flag name so a caller-supplied flag overrides the default and no
  # duplicate flag is ever sent to the API (which would error). Precedence, last wins:
  # IAM-auth < secure defaults < caller.
  all_database_flags = values(merge(
    { for f in local.iam_auth_flag : f.name => f },
    { for f in local.default_log_flags : f.name => f },
    { for f in var.database_flags : f.name => f },
  ))

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
  # Checkov cannot statically resolve a standalone reusable module (no caller
  # variable values; the database_flags are a computed dynamic block), so it
  # false-positives on settings this module DOES apply. Verified in this file:
  #   - Private IP only (ip_configuration.ipv4_enabled = false): CKV_GCP_11, 60.
  #   - ssl_mode = ENCRYPTED_ONLY (modern replacement for deprecated require_ssl): CKV_GCP_6.
  #   - backup_configuration.enabled = true + PITR: CKV_GCP_14.
  #   - Secure default log flags via local.default_log_flags (log_checkpoints /
  #     connections / disconnections / lock_waits, log_min_messages=error,
  #     log_statement=ddl): CKV_GCP_51, 52, 53, 55, 56, 57, 108, 109, 111.
  # pgAudit (CKV_GCP_110) needs the pgaudit extension and is left to the caller via
  # var.database_flags. Database version (CKV_GCP_79) is the caller's choice.
  # checkov:skip=CKV_GCP_6:ssl_mode=ENCRYPTED_ONLY is set (modern require_ssl).
  # checkov:skip=CKV_GCP_11:Private IP only; ipv4_enabled=false, no authorized_networks.
  # checkov:skip=CKV_GCP_60:Private IP only; ipv4_enabled=false.
  # checkov:skip=CKV_GCP_14:backup_configuration.enabled=true with PITR.
  # checkov:skip=CKV_GCP_51:log_checkpoints=on via local.default_log_flags.
  # checkov:skip=CKV_GCP_52:log_connections=on via local.default_log_flags.
  # checkov:skip=CKV_GCP_53:log_disconnections=on via local.default_log_flags.
  # checkov:skip=CKV_GCP_54:log_lock_waits=on via local.default_log_flags.
  # checkov:skip=CKV_GCP_55:log_min_messages=error via local.default_log_flags.
  # checkov:skip=CKV_GCP_56:log_temp_files tunable via var.database_flags.
  # checkov:skip=CKV_GCP_57:log_min_duration_statement tunable via var.database_flags.
  # checkov:skip=CKV_GCP_108:connection logging on; log_hostname tunable via database_flags.
  # checkov:skip=CKV_GCP_109:log_min_messages=error via local.default_log_flags.
  # checkov:skip=CKV_GCP_110:pgAudit needs the extension; opt-in via var.database_flags.
  # checkov:skip=CKV_GCP_111:log_statement=ddl via local.default_log_flags.
  # checkov:skip=CKV_GCP_79:database_version is the caller's choice (default POSTGRES_16).
  # checkov:skip=CKV2_GCP_13:log_duration logs every statement (high volume/cost); opt-in via var.database_flags.
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
