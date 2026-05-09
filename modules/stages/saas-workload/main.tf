# SaaS Workload Stage Module
#
# Composes three child modules to provision a complete SaaS environment:
#   1. supabase/environment  — Supabase project + settings + API keys (always)
#   2. supabase/vault-secrets — Vault bootstrap and reconcile (optional, gated by enable_vault_secrets)
#   3. vercel/project        — Vercel project + three environments + env vars (optional, gated by enable_vercel)
#
# Vercel and vault-secrets are gated by enable_vercel and enable_vault_secrets
# respectively — set them to false in the first apply when the downstream
# dependencies (Vercel team, Node.js in PATH) are not yet available.

module "supabase_environment" {
  source = "../../supabase/environment"

  organization_id      = var.supabase_organization_id
  project_name         = var.supabase_project_name
  database_password    = var.supabase_database_password
  region               = var.supabase_region
  disable_signup       = var.supabase_disable_signup
  mailer_autoconfirm   = var.supabase_mailer_autoconfirm
  password_min_length  = var.supabase_password_min_length
  api_max_rows         = var.supabase_api_max_rows
  db_schema            = var.supabase_db_schema
  db_extra_search_path = var.supabase_db_extra_search_path
  jwt_expiry           = var.supabase_jwt_expiry
}

module "vault_secrets" {
  count  = var.enable_vault_secrets ? 1 : 0
  source = "../../supabase/vault-secrets"

  postgres_url      = var.postgres_url
  supabase_ssl_cert = var.supabase_ssl_cert
  secrets           = var.vault_secrets
}

module "vercel_project" {
  count  = var.enable_vercel ? 1 : 0
  source = "../../vercel/project"

  project_name               = var.vercel_project_name
  team_id                    = var.vercel_team_id
  github_repo                = var.vercel_github_repo
  production_branch          = var.vercel_production_branch
  root_directory             = var.vercel_root_directory
  framework                  = var.vercel_framework
  serverless_function_region = var.vercel_serverless_region
  allowed_branches           = var.vercel_allowed_branches
  domains                    = var.vercel_domains

  qa_environment_variables     = var.vercel_qa_env_vars
  uat_environment_variables    = var.vercel_uat_env_vars
  prod_environment_variables   = var.vercel_prod_env_vars
  shared_environment_variables = var.vercel_shared_env_vars
}
