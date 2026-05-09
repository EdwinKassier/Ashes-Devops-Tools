variable "postgres_url" {
  description = <<-EOT
    Session-mode pooler URL (port 5432) for the target Supabase project.
    Transaction-mode pooler (port 6543) is NOT supported — CREATE EXTENSION
    and SECURITY DEFINER function invocation are unreliable through
    transaction-mode pooling.
    Format: postgresql://postgres.<project_ref>:<password>@<host>:5432/postgres
  EOT
  type        = string
  sensitive   = true
}

variable "supabase_ssl_cert" {
  description = <<-EOT
    Base64-encoded Supabase CA certificate chain for TLS verification of
    pooler connections. Required for Supabase pooler endpoints
    (*.pooler.supabase.com) — these use a self-signed certificate not
    present in standard CI runner CA stores.
    Default "" means no cert supplied; the scripts will fail fast for
    pooler endpoints unless PGSSL_INSECURE_NO_VERIFY=1 is set (break-glass).
  EOT
  type        = string
  sensitive   = true
  default     = ""
}

variable "secrets" {
  description = <<-EOT
    Desired state of the Supabase Vault as a flat map of name → value.
    The reconcile provisioner upserts every entry and deletes any vault row
    whose name is NOT in this map (within the IaC-managed namespace).

    Rules:
    - Names MUST be UPPER_SNAKE_CASE (^[A-Z][A-Z0-9_]*$) — this is the
      IaC namespace. Lowercase names are reserved for runtime-managed entries
      (per-tenant OAuth tokens) and will be rejected by the reconcile script.
    - Empty string values are treated as "absent" and the entry is deleted.
    - Removing a key from this map deletes the corresponding vault entry on
      the next apply.

    Example:
      secrets = {
        XERO_CLIENT_ID     = "my-xero-client-id"
        XERO_CLIENT_SECRET = "my-xero-client-secret"
        OPENAI_API_KEY     = "sk-..."
      }
  EOT
  type        = map(string)
  sensitive   = true
}
