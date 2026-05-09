# Example: bootstrap and reconcile the Supabase Vault for a project.
#
# Runtime requirements:
#   - Node.js >= 18 must be in PATH.
#   - SUPABASE_ACCESS_TOKEN env var should be set in CI for the Management
#     API path (bypasses the Supavisor pooler, avoiding "Tenant or user not
#     found" on GitHub Actions runners).
#   - SUPABASE_SSL_CERT (base64 CA bundle) is required for pooler connections;
#     fetch it from the Supabase dashboard or use the collects ensureSupabaseSslCert helper.
#
# In a real deployment, postgres_url comes from the supabase/environment
# module output and secrets come from CI environment variables.

locals {
  # Session-mode pooler URL (port 5432, NOT transaction-mode 6543).
  postgres_url = "postgresql://postgres.abcdefghijklmnopqrst:password@aws-0-eu-west-2.pooler.supabase.com:5432/postgres"
}

module "vault_secrets" {
  source = "../../"

  postgres_url      = local.postgres_url
  supabase_ssl_cert = "" # supply base64-encoded CA bundle for pooler connections

  secrets = {
    XERO_CLIENT_ID     = "my-client-id"
    XERO_CLIENT_SECRET = "my-client-secret"
    OPENAI_API_KEY     = "sk-proj-replace-with-real-key"
  }
}

