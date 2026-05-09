output "id" {
  description = "The Supabase project ref — a 20-character lowercase alphanumeric string used as the project identifier in all API calls."
  value       = supabase_project.this.id
}

output "name" {
  description = "The Supabase project display name."
  value       = supabase_project.this.name
}

output "database_password" {
  description = <<-EOT
    The database password as stored in Terraform state. This value is read from
    state, NOT re-fetched from the Supabase API (database_password is write-only:
    the provider schema has computed=false, so no refresh occurs). The lifecycle
    block ignores changes to this attribute after creation, meaning if the password
    is rotated via the Supabase dashboard this output will silently return the
    original creation-time value. Treat as a bootstrap convenience only.
  EOT
  value       = supabase_project.this.database_password
  sensitive   = true
}
