# SaaS-only deployable root — Supabase and/or Vercel, nothing else.
#
# Cloud selection is which workspaces you apply, not a runtime flag. This root
# declares no aws/google provider, so applying saas-<name> pulls in no cloud
# credentials. Within the root, enable_supabase / enable_vercel gate the two
# SaaS features independently — either can be off and the root still validates
# because modules/saas/stages/saas-workload defaults the other's inputs.

module "saas_workload" {
  source = "../../modules/saas/stages/saas-workload"

  # ── Feature flags ─────────────────────────────────────────────────────────
  enable_supabase      = local.enable_supabase
  enable_vercel        = local.enable_vercel
  enable_vault_secrets = var.enable_vault_secrets

  # ── Supabase pass-through (used only when enable_supabase = true) ──────────
  supabase_organization_id      = var.supabase_organization_id
  supabase_project_name         = var.supabase_project_name
  supabase_database_password    = var.supabase_database_password
  supabase_region               = var.supabase_region
  supabase_disable_signup       = var.supabase_disable_signup
  supabase_mailer_autoconfirm   = var.supabase_mailer_autoconfirm
  supabase_password_min_length  = var.supabase_password_min_length
  supabase_api_max_rows         = var.supabase_api_max_rows
  supabase_db_schema            = var.supabase_db_schema
  supabase_db_extra_search_path = var.supabase_db_extra_search_path
  supabase_jwt_expiry           = var.supabase_jwt_expiry

  # ── Vault pass-through (used only when enable_vault_secrets = true) ─────────
  postgres_url      = var.postgres_url
  supabase_ssl_cert = var.supabase_ssl_cert
  vault_secrets     = var.vault_secrets

  # ── Vercel pass-through (used only when enable_vercel = true) ──────────────
  vercel_project_name      = var.vercel_project_name
  vercel_team_id           = var.vercel_team_id
  vercel_github_repo       = var.vercel_github_repo
  vercel_production_branch = var.vercel_production_branch
  vercel_root_directory    = var.vercel_root_directory
  vercel_framework         = var.vercel_framework
  vercel_serverless_region = var.vercel_serverless_region
  vercel_allowed_branches  = var.vercel_allowed_branches
  vercel_domains           = var.vercel_domains

  vercel_qa_env_vars   = var.vercel_qa_env_vars
  vercel_uat_env_vars  = var.vercel_uat_env_vars
  vercel_prod_env_vars = var.vercel_prod_env_vars
  # Caller-supplied shared env vars plus any resolved cross-cloud references.
  vercel_shared_env_vars = local.effective_vercel_shared_env_vars
}

# ── Cross-cloud wiring seam (audit H9, option C — frontend-URL seam) ──────────
#
# A SaaS root can consume an output from another cloud's root (AWS or GCP)
# WITHOUT configuring that cloud's provider: terraform_remote_state reads from
# state at plan time and needs only the TFC organization, no cloud credentials.
# This keeps `terraform validate -backend=false` credential-free (what CI runs).
#
# Opt-in via var.cross_cloud_references. Default empty: no upstream state is read
# and this root stays standalone. Each reference resolves an upstream output (for
# example a GCP/AWS runtime's API endpoint) into a shared Vercel env var, so the
# frontend learns the backend URL.

data "terraform_remote_state" "cross_cloud" {
  for_each = local.cross_cloud_workspaces

  backend = "cloud"
  config = {
    organization = local.tfc_organization
    workspaces = {
      name = each.value
    }
  }
}

locals {
  # Distinct upstream workspaces referenced (for_each key = workspace name).
  cross_cloud_workspaces = toset([for r in values(var.cross_cloud_references) : r.workspace_name])

  # Resolve each reference to a Vercel shared env var.
  cross_cloud_env_vars = [
    for k, r in var.cross_cloud_references : {
      key       = r.vercel_env_key
      value     = tostring(data.terraform_remote_state.cross_cloud[r.workspace_name].outputs[r.output_key])
      sensitive = r.sensitive
    }
  ]

  effective_vercel_shared_env_vars = concat(var.vercel_shared_env_vars, local.cross_cloud_env_vars)
}
