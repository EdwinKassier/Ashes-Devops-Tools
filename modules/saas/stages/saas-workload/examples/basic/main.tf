# The module source below is pinned to a release tag (bumped by release-please
# through the x-release-please-version marker). To try local changes, replace it
# with the relative path "../../".
#
# Example: provision a complete SaaS QA environment — Supabase project + Vercel project.
# This is the end state, after three applies:
#
# Phase 1 (first apply): set enable_vault_secrets = false and enable_vercel = false.
#   The Supabase project is created. Note the project_id output.
#   Obtain the postgres_url from the Supabase dashboard (session-mode pooler)
#   and download the project's CA certificate (Database settings, SSL configuration).
#
# Phase 2 (second apply): set enable_vault_secrets = true and supply postgres_url
#   and supabase_ssl_cert. Vault is bootstrapped and secrets are reconciled.
#
# Phase 3 (third apply, once the Vercel team is ready): set enable_vercel = true.
#   The Vercel project is created.
#
# Passwords, the connection URL, the certificate and secret values are
# sensitive variables (TF_VAR_* or sensitive Terraform Cloud variables).

locals {
  organization_id = "abcdefghijklmnop"

  vercel_team_id = "team_abcdefghijklmno"
  vercel_repo    = "example-org/my-app"
}

module "qa_saas_workload" {
  # checkov:skip=CKV_TF_1:Published example pinned to the release tag that release-please bumps (x-release-please-version); a commit SHA would break that flow. Release tags are not yet protected as immutable (tracked in docs/known-gaps.md).
  source = "git::https://github.com/EdwinKassier/Ashes-Devops-Tools.git//modules/saas/stages/saas-workload?ref=v0.1.0" # x-release-please-version

  # Supabase
  supabase_organization_id    = local.organization_id
  supabase_project_name       = "my-app-qa"
  supabase_database_password  = var.database_password
  supabase_region             = "eu-west-2"
  supabase_mailer_autoconfirm = true # QA only
  supabase_disable_signup     = false

  # Vault (phase 2)
  enable_vault_secrets = true
  postgres_url         = var.postgres_url
  supabase_ssl_cert    = var.supabase_ssl_cert
  vault_secrets        = var.vault_secrets

  # Vercel (phase 3)
  enable_vercel            = true
  vercel_project_name      = "my-app"
  vercel_team_id           = local.vercel_team_id
  vercel_github_repo       = local.vercel_repo
  vercel_production_branch = "main"
  vercel_root_directory    = "apps/nextjs"
  vercel_serverless_region = "lhr1"

  # A QA workspace binds only the QA domain; production domains belong to the
  # production workspace.
  vercel_domains = [
    { domain = "qa.example.com", environment = "qa" },
  ]

  # Add NEXT_PUBLIC_SUPABASE_ANON_KEY from the supabase_anon_key output after
  # phase 1.
  vercel_qa_env_vars = [
    { key = "NEXT_PUBLIC_SUPABASE_URL", value = "https://abcdefghijklmnopqrst.supabase.co" },
    { key = "NEXT_PUBLIC_APP_URL", value = "https://qa.example.com" },
  ]
}
