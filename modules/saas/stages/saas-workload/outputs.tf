# ── Supabase outputs ───────────────────────────────────────────────────────────

output "supabase_project_id" {
  description = "The Supabase project ref. Null when enable_supabase = false."
  value       = var.enable_supabase ? module.supabase_environment[0].project_id : null
}

output "supabase_api_url" {
  description = "The Supabase project REST API URL. Null when enable_supabase = false."
  value       = var.enable_supabase ? module.supabase_environment[0].api_url : null
}

output "supabase_anon_key" {
  description = "The Supabase anon key (public credential). Not marked sensitive by design — see supabase/environment module. Null when enable_supabase = false."
  value       = var.enable_supabase ? module.supabase_environment[0].anon_key : null
}

output "supabase_service_role_key" {
  description = "The Supabase service role key. Treat as a secret. Null when enable_supabase = false."
  value       = var.enable_supabase ? module.supabase_environment[0].service_role_key : null
  sensitive   = true
}

output "supabase_database_password" {
  description = "The initial Supabase database password. Null when enable_supabase = false."
  value       = var.enable_supabase ? module.supabase_environment[0].database_password : null
  sensitive   = true
}

# ── Vault outputs ──────────────────────────────────────────────────────────────

output "vault_managed_secret_names" {
  description = "Names of vault secrets managed by this module. Null when enable_vault_secrets = false."
  value       = var.enable_vault_secrets ? module.vault_secrets[0].managed_secret_names : null
}

# ── Vercel outputs ─────────────────────────────────────────────────────────────

output "vercel_project_id" {
  description = "The Vercel project ID. Null when enable_vercel = false."
  value       = var.enable_vercel ? module.vercel_project[0].project_id : null
}

output "vercel_uat_environment_id" {
  description = "The Vercel UAT custom environment ID. Null when enable_vercel = false."
  value       = var.enable_vercel ? module.vercel_project[0].uat_environment_id : null
}
