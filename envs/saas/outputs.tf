# Re-export the saas-workload module outputs. Each is null when the
# corresponding feature flag is false (see modules/stages/saas-workload/outputs.tf).

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
