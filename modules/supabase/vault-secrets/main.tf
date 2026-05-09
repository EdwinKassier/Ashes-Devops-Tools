# Supabase Vault Secrets Module
#
# Bootstraps the Supabase Vault with three SECURITY DEFINER helper functions
# and reconciles its contents against a desired-state map.
#
# Architecture:
#   1. bootstrap (null_resource) — installs the vault extension and creates
#      public.upsert_vault_secret, public.delete_vault_secret, and
#      public.delete_vault_secrets_by_prefix. Idempotent; runs whenever the
#      bootstrap script file changes.
#   2. reconcile (null_resource) — upserts every entry in var.secrets and
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

resource "null_resource" "bootstrap" {
  triggers = {
    script_hash = filesha256("${path.module}/scripts/bootstrap.mjs")
    # nonsensitive(sha256(...)): postgres_url is sensitive = true. Terraform >= 1.9
    # refuses to store a sensitive value in triggers (map(string) is non-sensitive).
    # sha256 is one-way so exposing the digest does not leak the original value.
    db = nonsensitive(sha256(var.postgres_url))
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

resource "null_resource" "reconcile" {
  triggers = {
    # nonsensitive(sha256(...)): both var.secrets and var.postgres_url are sensitive = true.
    # Triggers are map(string) and cannot hold sensitive values. sha256 is one-way.
    desired_hash   = nonsensitive(sha256(jsonencode(var.secrets)))
    reconcile_hash = filesha256("${path.module}/scripts/reconcile.mjs")
    db             = nonsensitive(sha256(var.postgres_url))
  }

  depends_on = [null_resource.bootstrap]

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
