# ── Supabase outputs ───────────────────────────────────────────────────────────

output "supabase_project_id" {
  description = "The Supabase project ref."
  value       = module.supabase_environment.project_id
}

output "supabase_api_url" {
  description = "The Supabase project REST API URL."
  value       = module.supabase_environment.api_url
}

output "supabase_anon_key" {
  description = "The Supabase anon key (public credential). Not marked sensitive by design — see supabase/environment module."
  value       = module.supabase_environment.anon_key
}

output "supabase_service_role_key" {
  description = "The Supabase service role key. Treat as a secret."
  value       = module.supabase_environment.service_role_key
  sensitive   = true
}

output "supabase_database_password" {
  description = "The initial Supabase database password."
  value       = module.supabase_environment.database_password
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
