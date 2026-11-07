/**
 * Copyright 2023 Ashes
 *
 * Secret Manager Module - Main Configuration
 *
 * Creates application secret CONTAINERS in Secret Manager. Secret values are not
 * managed here by default — only container metadata, replication and IAM — so no
 * plaintext lands in Terraform state. An optional initial version can be supplied
 * per secret via var.secret_values for bootstrap/non-production use.
 */

locals {
  # Flatten secret_name => [members] into one binding per (secret, member) pair.
  secret_accessor_bindings = merge([
    for secret_name, members in var.secret_accessors : {
      for member in members :
      "${secret_name}::${member}" => {
        secret = secret_name
        member = member
      }
    }
  ]...)
}

# Deletion protection guard — present only when enable_deletion_protection = true.
# prevent_destroy must be a static literal, so the guard carries it on behalf of the
# whole module and is created conditionally.
resource "terraform_data" "deletion_protection_guard" {
  count = var.enable_deletion_protection ? 1 : 0

  input = var.project_id

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_secret_manager_secret" "this" {
  for_each = var.secrets

  project   = var.project_id
  secret_id = each.key
  labels    = merge(var.labels, each.value.labels)

  replication {
    # Automatic (multi-region) replication unless explicit regions are supplied.
    dynamic "auto" {
      for_each = length(each.value.replication.user_managed_regions) == 0 ? [1] : []
      content {
        dynamic "customer_managed_encryption" {
          for_each = each.value.kms_key_name != null ? [each.value.kms_key_name] : []
          content {
            kms_key_name = customer_managed_encryption.value
          }
        }
      }
    }

    # User-managed replication across an explicit set of regions.
    dynamic "user_managed" {
      for_each = length(each.value.replication.user_managed_regions) > 0 ? [1] : []
      content {
        dynamic "replicas" {
          for_each = each.value.replication.user_managed_regions
          content {
            location = replicas.value

            dynamic "customer_managed_encryption" {
              for_each = each.value.kms_key_name != null ? [each.value.kms_key_name] : []
              content {
                kms_key_name = customer_managed_encryption.value
              }
            }
          }
        }
      }
    }
  }
}

# Optional initial secret versions — created ONLY for names present in secret_values.
resource "google_secret_manager_secret_version" "this" {
  # for_each cannot take a sensitive value; iterate the (non-secret) names and
  # look the sensitive value up by key so only secret_data stays sensitive.
  # Secrets flagged ephemeral_value join the set from var.secrets (non-ephemeral),
  # since an ephemeral map's keys cannot drive for_each.
  for_each = setunion(
    nonsensitive(toset(keys(var.secret_values))),
    toset([for name, cfg in var.secrets : name if cfg.ephemeral_value]),
  )

  secret = google_secret_manager_secret.this[each.key].id

  # Write-only (Terraform >= 1.11): the plaintext is sent to the API but NEVER
  # persisted in plan or state. Bump secret_value_versions[<name>] to push a new
  # value (write-only attributes cannot be diffed).
  # google 8.x types secret_data_wo_version as a String (state migrates N to
  # "N") and requires it alongside secret_data_wo; a "0" counts as unset and
  # forces replacement, so the counter stays a positive integer, stringified.
  secret_data_wo         = var.secrets[each.key].ephemeral_value ? var.ephemeral_secret_values[each.key] : var.secret_values[each.key]
  secret_data_wo_version = tostring(lookup(var.secret_value_versions, each.key, 1))
}

# Per-secret accessor bindings (roles/secretmanager.secretAccessor).
resource "google_secret_manager_secret_iam_member" "accessor" {
  for_each = local.secret_accessor_bindings

  project   = var.project_id
  secret_id = google_secret_manager_secret.this[each.value.secret].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = each.value.member
}
