# Example: provision a complete SaaS QA environment — Supabase project + Vercel project.
# Replace all locals with real values or remote state outputs.
#
# Phase 1 (first apply): set enable_vercel = false and enable_vault_secrets = false.
#   The Supabase project is created. Note the project_id output.
#   Obtain the postgres_url from the Supabase dashboard (session-mode pooler).
#   Fetch the SUPABASE_SSL_CERT for pooler connections.
#
# Phase 2 (second apply): set enable_vault_secrets = true and supply postgres_url.
#   Vault is bootstrapped and secrets are reconciled.
#
# Phase 3 (third apply, once Vercel team is ready): set enable_vercel = true.
#   Vercel project is created with Supabase outputs as env vars.

locals {
  organization_id   = "abcdefghijklmnop"
  database_password = "super-secret-password-16chars!"

  vercel_team_id = "team_abcdefghijklmno"
  vercel_repo    = "myorg/my-app"

  # After phase 1, populate these from Supabase dashboard or module outputs.
  postgres_url      = "postgresql://postgres.abcdefghijklmnopqrst:password@aws-0-eu-west-2.pooler.supabase.com:5432/postgres"
  supabase_ssl_cert = "" # base64-encoded CA bundle for pooler connections
}

module "qa_saas_workload" {
  source = "../../"

  # Supabase
  supabase_organization_id    = local.organization_id
  supabase_project_name       = "my-app-qa"
  supabase_database_password  = local.database_password
  supabase_region             = "eu-west-2"
  supabase_mailer_autoconfirm = true # QA only
  supabase_disable_signup     = false

  # Vault (phase 2)
  enable_vault_secrets = true
  postgres_url         = local.postgres_url
  supabase_ssl_cert    = local.supabase_ssl_cert
  vault_secrets = {
    XERO_CLIENT_ID     = "my-xero-client-id"
    XERO_CLIENT_SECRET = "my-xero-client-secret"
  }

  # Vercel (phase 3)
  enable_vercel            = true
  vercel_project_name      = "my-app"
  vercel_team_id           = local.vercel_team_id
  vercel_github_repo       = local.vercel_repo
  vercel_production_branch = "main"
  vercel_root_directory    = "apps/nextjs"
  vercel_serverless_region = "lhr1"

  vercel_domains = [
    { domain = "qa.my-app.com", environment = "qa" },
    { domain = "my-app.com", environment = "production" },
  ]

  vercel_qa_env_vars = [
    { key = "NEXT_PUBLIC_SUPABASE_URL", value = "https://abcdefghijklmnopqrst.supabase.co" },
    { key = "NEXT_PUBLIC_SUPABASE_ANON_KEY", value = "eyJ..." },
    { key = "NEXT_PUBLIC_APP_URL", value = "https://qa.my-app.com" },
  ]
}

