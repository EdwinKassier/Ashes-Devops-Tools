variable "database_password" {
  description = "Postgres password of the new Supabase project (at least 16 characters). Set it with TF_VAR_database_password or a sensitive Terraform Cloud variable."
  type        = string
  sensitive   = true
}
