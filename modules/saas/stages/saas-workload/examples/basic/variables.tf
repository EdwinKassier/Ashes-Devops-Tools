variable "database_password" {
  description = "Postgres password of the Supabase project (at least 16 characters)."
  type        = string
  sensitive   = true
}

variable "postgres_url" {
  description = "Session-mode pooler URL of the Supabase project (port 5432)."
  type        = string
  sensitive   = true
}

variable "supabase_ssl_cert" {
  description = "Base64-encoded CA certificate of the Supabase project, required for pooler connections."
  type        = string
  sensitive   = true
}

variable "vault_secrets" {
  description = "Secrets to store in the Supabase Vault, as UPPER_SNAKE_CASE name to value (for example XERO_CLIENT_ID)."
  type        = map(string)
  sensitive   = true
}
