variable "postgres_url" {
  description = "Session-mode pooler URL (port 5432, not transaction-mode 6543), for example postgresql://postgres.<project-ref>:<password>@aws-0-eu-west-2.pooler.supabase.com:5432/postgres."
  type        = string
  sensitive   = true
}

variable "supabase_ssl_cert" {
  description = "Base64-encoded CA certificate of the Supabase project, required for pooler connections."
  type        = string
  sensitive   = true
}

variable "xero_client_id" {
  description = "Example application secret stored in the vault."
  type        = string
  sensitive   = true
}

variable "xero_client_secret" {
  description = "Example application secret stored in the vault."
  type        = string
  sensitive   = true
}
