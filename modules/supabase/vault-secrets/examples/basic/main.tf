# Example: bootstrap and reconcile the Supabase Vault for a project.
#
# Runtime requirements:
#   - Node.js >= 18 must be in PATH.
#   - Script dependencies are installed automatically during apply
#     (npm ci --ignore-scripts from the committed lockfile); npm must be in PATH.
#   - SUPABASE_ACCESS_TOKEN env var should be set in CI for the Management
#     API path (bypasses the Supavisor pooler, avoiding "Tenant or user not
#     found" on GitHub Actions runners).
#   - Pooler connections (*.pooler.supabase.com) need the project's CA
#     certificate: download it from the Supabase dashboard (Database settings,
#     SSL configuration) and pass it base64-encoded as supabase_ssl_cert. The
#     scripts fail fast without it.
#
# The connection URL, the certificate and the secret values are sensitive
# variables: set them with TF_VAR_* or sensitive Terraform Cloud variables,
# never in code. In a real deployment postgres_url is the session-mode pooler
# URL of the project from supabase/environment.

module "vault_secrets" {
  source = "../../"

  postgres_url      = var.postgres_url
  supabase_ssl_cert = var.supabase_ssl_cert

  secrets = {
    XERO_CLIENT_ID     = var.xero_client_id
    XERO_CLIENT_SECRET = var.xero_client_secret
  }
}
