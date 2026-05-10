output "project_ref" {
  description = "The Supabase project ref this settings resource manages."
  value       = supabase_settings.this.project_ref
}

output "settings_id" {
  description = "The Terraform resource ID of the supabase_settings resource."
  value       = supabase_settings.this.id
}
