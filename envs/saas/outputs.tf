# Re-export the saas-workload module outputs. Each is null when the
# corresponding feature flag is false (see modules/saas/stages/saas-workload/outputs.tf).

# ── Supabase ─────────────────────────────────────────────────────────────────

output "supabase_project_id" {
  description = "The Supabase project ref. Null when enable_supabase = false."
  value       = module.saas_workload.supabase_project_id
}

output "supabase_api_url" {
  description = "The Supabase project REST API URL. Null when enable_supabase = false."
  value       = module.saas_workload.supabase_api_url
}

output "supabase_anon_key" {
  description = "The Supabase anon key (public credential). Null when enable_supabase = false."
  value       = module.saas_workload.supabase_anon_key
}

output "supabase_service_role_key" {
  description = "The Supabase service role key. Treat as a secret. Null when enable_supabase = false."
  value       = module.saas_workload.supabase_service_role_key
  sensitive   = true
}

output "supabase_database_password" {
  description = "The initial Supabase database password. Null when enable_supabase = false."
  value       = module.saas_workload.supabase_database_password
  sensitive   = true
}

# Non-sensitive rotation signal for the workload secret bridge
# (enable_saas_secret_bridge in envs/aws/workload and envs/gcp/workload). Write-only
# arguments cannot be diffed, so the bridged secret is re-pushed only when this
# number changes: bump saas.bridge_rotation after rotating a bridged secret.
output "bridge_version" {
  description = "Rotation counter for the workload secret bridge (saas.bridge_rotation, default 1). Non-sensitive: a bridging workload reads it as its write-only *_wo_version."
  value       = local.bridge_rotation
}

# ── Vault ────────────────────────────────────────────────────────────────────

output "vault_managed_secret_names" {
  description = "Names of vault secrets managed by this root. Null when enable_vault_secrets = false."
  value       = module.saas_workload.vault_managed_secret_names
}

# ── Vercel ───────────────────────────────────────────────────────────────────

output "vercel_project_id" {
  description = "The Vercel project ID. Null when enable_vercel = false."
  value       = module.saas_workload.vercel_project_id
}

output "vercel_uat_environment_id" {
  description = "The Vercel UAT custom environment ID. Null when enable_vercel = false."
  value       = module.saas_workload.vercel_uat_environment_id
}

output "cross_cloud_injected_env_keys" {
  description = "Vercel shared env var keys injected from cross_cloud_references. Empty when the frontend-URL seam is unused."
  value       = [for v in local.cross_cloud_env_vars : v.key]
}

# The stage validates these too, but its messages name stage variables. A
# forker configures saas.stacks.<stack> / saas.defaults, so fail here first
# with errors that name the config keys.
output "stack" {
  description = "The SaaS stack key this workspace deploys (saas.stacks.<stack>)."
  value       = local.stack

  precondition {
    condition     = !local.enable_supabase || can(regex("^[a-z0-9]{8,}$", local.supabase_organization_id))
    error_message = "Supabase is enabled but no organization ID is set: add saas.defaults.supabase.organization_id (or saas.stacks.${local.stack}.supabase.organization_id) to config/landing-zone.yaml, or set supabase_organization_id."
  }

  precondition {
    condition     = !local.enable_supabase || (length(local.supabase_project_name) >= 3 && length(local.supabase_project_name) <= 64)
    error_message = "Supabase is enabled but saas.stacks.${local.stack}.supabase.project_name is missing (3-64 chars) in config/landing-zone.yaml (or set supabase_project_name)."
  }

  precondition {
    condition     = !local.enable_vercel || length(local.vercel_team_id) > 0
    error_message = "Vercel is enabled but no team ID is set: add saas.defaults.vercel.team_id (or saas.stacks.${local.stack}.vercel.team_id) to config/landing-zone.yaml, or set vercel_team_id."
  }

  precondition {
    condition     = !local.enable_vercel || (can(regex("^[a-z0-9][a-z0-9-]{0,98}[a-z0-9]$", local.vercel_project_name)) && can(regex("^[^/]+/[^/]+$", local.vercel_github_repo)))
    error_message = "Vercel is enabled but saas.stacks.${local.stack}.vercel.project_name (lowercase, 2-100 chars) and/or .github_repo (owner/repo) are missing in config/landing-zone.yaml."
  }
}
