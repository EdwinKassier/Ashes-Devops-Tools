# SaaS-only deployable root — Supabase and/or Vercel, nothing else.
#
# Cloud selection is which workspaces you apply, not a runtime flag. This root
# declares no aws/google provider, so applying saas-<name> pulls in no cloud
# credentials. Within the root, enable_supabase / enable_vercel gate the two
# SaaS features independently — either can be off and the root still validates
# because modules/stages/saas-workload defaults the other's inputs.

module "saas_workload" {
  source = "../../modules/stages/saas-workload"

  # ── Feature flags ─────────────────────────────────────────────────────────
  enable_supabase      = var.enable_supabase
  enable_vercel        = var.enable_vercel
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

  vercel_qa_env_vars     = var.vercel_qa_env_vars
  vercel_uat_env_vars    = var.vercel_uat_env_vars
  vercel_prod_env_vars   = var.vercel_prod_env_vars
  vercel_shared_env_vars = var.vercel_shared_env_vars
}

# ── OPTIONAL: cross-cloud wiring seam (Convention 5) ─────────────────────────
#
# A SaaS root can consume an output from another cloud's root (AWS or GCP)
# WITHOUT ever configuring that cloud's provider: terraform_remote_state reads
# from state at plan time and needs only the TFC organization — no cloud creds.
# This keeps `terraform validate -backend=false` credential-free (what CI runs).
#
# Everything below is COMMENTED so this root validates standalone. Uncomment,
# set var.tfc_organization + var.upstream_workspace_name, and wire the output
# into a Vercel env var or Supabase input as shown. It is inert until then.
#
# data "terraform_remote_state" "upstream" {
#   # Guarded: only reads state when an upstream workspace name is configured.
#   count   = var.upstream_workspace_name == null ? 0 : 1
#   backend = "cloud"
#   config = {
#     organization = var.tfc_organization
#     workspaces = {
#       # e.g. "aws-workload-production" or "apps-production"
#       name = var.upstream_workspace_name
#     }
#   }
# }
#
# locals {
#   # Inert when the remote state is not wired in; resolves from state otherwise.
#   upstream_api_endpoint = try(
#     data.terraform_remote_state.upstream[0].outputs.api_endpoint,
#     null,
#   )
# }
#
# Feed it into a Vercel env var (append to var.vercel_shared_env_vars), e.g.:
#   vercel_shared_env_vars = concat(var.vercel_shared_env_vars, compact([
#     local.upstream_api_endpoint == null ? null : jsonencode({
#       key = "UPSTREAM_API_URL", value = local.upstream_api_endpoint
#     })
#   ]))
# ...or into a Supabase input the same way. Because the lookup resolves from
# state (not the live cloud API), no AWS/GCP credentials are ever required.
