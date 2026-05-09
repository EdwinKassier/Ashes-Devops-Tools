output "project_id" {
  description = "The Supabase project ref (20-char alphanumeric)."
  value       = module.project.id
}

output "project_name" {
  description = "The Supabase project display name."
  value       = module.project.name
}

output "api_url" {
  description = "The Supabase project REST API URL (https://<project_ref>.supabase.co)."
  value       = "https://${module.project.id}.supabase.co"
}

output "anon_key" {
  description = <<-EOT
    The Supabase anon key (public credential). Intentionally NOT marked sensitive
    because anon_key is a public key safe to embed in client-side code, and
    marking it sensitive causes Terraform to refuse its use in for-expression
    filter conditions — a pattern callers need when wiring multi-environment
    Vercel env vars. The service_role_key IS sensitive.
  EOT
  # nonsensitive(): the supabase provider marks anon_key as sensitive=true in its
  # data source schema. Terraform ≥ 1.2 refuses to emit a root-module output that
  # references a sensitive value without either `sensitive = true` or a
  # nonsensitive() wrapper. We use nonsensitive() because anon_key is a public
  # client-side credential — no security reason to redact it — and callers rely
  # on the non-sensitive classification for for_each keys and conditionals.
  # Confirmed: `data.supabase_apikeys.this.anon_key` schema: sensitive=True.
  value = nonsensitive(data.supabase_apikeys.this.anon_key)
}

output "service_role_key" {
  description = "The Supabase service role key. Treat as a secret — grants full database access bypassing Row Level Security."
  value       = data.supabase_apikeys.this.service_role_key
  sensitive   = true
}

output "database_password" {
  description = "The initial database password set at project creation."
  value       = module.project.database_password
  sensitive   = true
}
