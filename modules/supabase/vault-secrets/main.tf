# Supabase Vault Secrets Module
#
# Bootstraps the Supabase Vault with two SECURITY DEFINER helper functions
# and reconciles its contents against a desired-state map.
#
# Architecture:
#   1. bootstrap (terraform_data) — installs the vault extension and creates
#      iac_vault.upsert_vault_secret and iac_vault.delete_vault_secret in a
#      private schema that PostgREST does not expose (never add iac_vault to
#      the API "exposed schemas"). EXECUTE is revoked from PUBLIC, anon and
#      authenticated; both helpers refuse names outside the IaC namespace.
#      Drops the legacy public.* helpers of earlier versions. Idempotent;
#      runs whenever the bootstrap script or target database changes.
#   2. reconcile (terraform_data) — upserts every entry in var.secrets and
#      deletes any IaC-managed vault row NOT in var.secrets. Runs whenever
#      the desired-state map or reconcile script changes.
#
# Runtime requirements:
#   - Node.js >= 18 must be available in the execution environment.
#   - SUPABASE_ACCESS_TOKEN env var enables the Management API path (preferred
#     in CI). The scripts fall back to a direct pg Pool connection when the
#     token is absent (local dev) or the Management API is unreachable.
#
# IaC namespace: only vault secrets whose names match ^[A-Z][A-Z0-9_]*$
# (UPPER_SNAKE_CASE) are managed by this module. Runtime-managed entries
# (per-tenant OAuth tokens with lowercase names) are never touched.

# ── Resource type ─────────────────────────────────────────────────────────────
# These were null_resource in earlier versions. They are now built-in
# terraform_data (no hashicorp/null provider needed for new resources); the
# moved blocks at the bottom migrate existing state in place (Terraform >= 1.9
# supports the null_resource -> terraform_data cross-type move), so upgrading
# does NOT re-run a provisioner merely because the type changed.
#
# ── Trigger hashing (no secret material in state) ─────────────────────────────
# Terraform >= 1.9 refuses raw sensitive values in triggers, and a plain
# sha256 of a secret is brute-forceable when the secret is low-entropy. So:
#   - db_identity hashes the postgres URL with its PASSWORD STRIPPED. It only
#     needs to change when the target database (user/host/port/db) changes; the
#     state digest therefore contains no secret at all. A password rotation no
#     longer re-runs bootstrap (it is idempotent and does not depend on it).
#   - desired_hash must detect any change to the secret VALUES, so it cannot
#     avoid hashing them. It is keyed with the database password (high-entropy
#     and not stored in this module's state): sha256(postgres_url || desired).
#     A state reader cannot test guesses of a secret value without also knowing
#     the database password. Rotating the DB password re-runs reconcile once,
#     which is harmless (reconcile is idempotent).
locals {
  db_identity = nonsensitive(sha256(replace(var.postgres_url, "/^([A-Za-z][A-Za-z0-9+.-]*://[^:@/]*):[^@/]*@/", "$1@")))
  desired_keyed_hash = nonsensitive(sha256(join("\n", [
    "vault-secrets/desired/v2",
    var.postgres_url,
    jsonencode(var.secrets),
  ])))
}

# Install the Node dependencies the provisioner scripts import (pg) reproducibly
# before any script runs:
#   - `npm ci` installs exactly the committed package-lock.json (integrity-
#     checked) and fails loudly up front rather than mid-apply.
#   - --ignore-scripts: never execute dependency lifecycle scripts on the apply
#     runner (supply-chain hardening). pg and its dependencies are pure JS and
#     ship no install scripts; the optional native binding (pg-native) is not
#     used.
#   - --no-audit --no-fund: no extra calls to the registry's audit endpoint and
#     no noise in the apply log.
resource "terraform_data" "npm_install" {
  triggers_replace = {
    lock_hash = filesha256("${path.module}/scripts/package-lock.json")
  }

  provisioner "local-exec" {
    command     = "npm ci --ignore-scripts --no-audit --no-fund --prefix ${path.module}/scripts"
    working_dir = path.root
  }
}

resource "terraform_data" "bootstrap" {
  depends_on = [terraform_data.npm_install]

  triggers_replace = {
    script_hash = filesha256("${path.module}/scripts/bootstrap.mjs")
    db          = local.db_identity
  }

  provisioner "local-exec" {
    command     = "node ${path.module}/scripts/bootstrap.mjs"
    working_dir = path.root

    environment = {
      POSTGRES_URL      = var.postgres_url
      SUPABASE_SSL_CERT = var.supabase_ssl_cert
    }
  }
}

resource "terraform_data" "reconcile" {
  triggers_replace = {
    desired_hash   = local.desired_keyed_hash
    reconcile_hash = filesha256("${path.module}/scripts/reconcile.mjs")
    db             = local.db_identity
  }

  depends_on = [terraform_data.bootstrap]

  provisioner "local-exec" {
    command     = "node ${path.module}/scripts/reconcile.mjs"
    working_dir = path.root

    environment = {
      POSTGRES_URL       = var.postgres_url
      VAULT_DESIRED_JSON = jsonencode(var.secrets)
      SUPABASE_SSL_CERT  = var.supabase_ssl_cert
      # VAULT_ALLOW_EMPTY_DESIRED is intentionally omitted — pass it directly
      # in the environment running terraform apply when intentionally wiping
      # the vault (e.g. VAULT_ALLOW_EMPTY_DESIRED=1 terraform apply).
    }
  }
}

# ── State migration from null_resource (module versions before 2026-11) ───────
moved {
  from = null_resource.npm_install
  to   = terraform_data.npm_install
}

moved {
  from = null_resource.bootstrap
  to   = terraform_data.bootstrap
}

moved {
  from = null_resource.reconcile
  to   = terraform_data.reconcile
}
