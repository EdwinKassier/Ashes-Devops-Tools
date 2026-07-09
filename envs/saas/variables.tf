# ── Terraform Cloud / cross-wiring ───────────────────────────────────────────

variable "tfc_organization" {
  description = "Terraform Cloud organization name. Only consumed by the optional cross-cloud remote-state seam in main.tf (commented out by default). Leave null for a standalone SaaS deployment."
  type        = string
  default     = null
}

variable "upstream_workspace_name" {
  description = "Optional. Name of an upstream AWS/GCP workspace to read cross-cloud outputs from via the commented terraform_remote_state seam in main.tf. Leave null (default) to keep this root fully standalone."
  type        = string
  default     = null
}

# ── Feature flags ─────────────────────────────────────────────────────────────

variable "enable_supabase" {
  description = "Provision the Supabase project. Set false for a Vercel-only deployment — the Supabase inputs may then be left at their defaults."
  type        = bool
  default     = true
}

variable "enable_vercel" {
  description = "Provision the Vercel project. Set false for a Supabase-only deployment — the Vercel inputs may then be left at their defaults."
  type        = bool
  default     = true
}

variable "enable_vault_secrets" {
  description = "Bootstrap and reconcile the Supabase Vault. Requires Node.js >= 18 in the execution environment and var.postgres_url. Default false."
  type        = bool
  default     = false
}

# ── Supabase pass-through (required when enable_supabase = true) ────────────────

variable "supabase_organization_id" {
  description = "Supabase organisation ID. Required when enable_supabase = true; at least 8 lowercase alphanumeric characters."
  type        = string
  default     = ""
}

variable "supabase_project_name" {
  description = "Display name for the Supabase project (3–64 chars). Required when enable_supabase = true."
  type        = string
  default     = ""
}

variable "supabase_database_password" {
  description = "Initial Postgres database password (min 16 chars). Required when enable_supabase = true. Ignored after initial creation."
  type        = string
  sensitive   = true
  default     = ""
}

variable "supabase_region" {
  description = "Supabase deployment region slug (e.g. 'eu-west-2')."
  type        = string
  default     = "eu-west-2"
}

variable "supabase_disable_signup" {
  description = "Disable new user sign-ups. Recommended true for production."
  type        = bool
  default     = false
}

variable "supabase_mailer_autoconfirm" {
  description = "Auto-confirm email addresses. QA only; disable for production."
  type        = bool
  default     = false
}

variable "supabase_password_min_length" {
  description = "Minimum password length for user accounts (6–100)."
  type        = number
  default     = 12
}

variable "supabase_api_max_rows" {
  description = "Maximum rows returned by a single REST API request (100–100 000)."
  type        = number
  default     = 1000
}

variable "supabase_db_schema" {
  description = "Comma-separated list of Postgres schemas exposed via the REST API."
  type        = string
  default     = "public,graphql_public"
}

variable "supabase_db_extra_search_path" {
  description = "Comma-separated list of schemas appended to the Postgres search_path."
  type        = string
  default     = "public,extensions"
}

variable "supabase_jwt_expiry" {
  description = "JWT access token expiry in seconds (300–604 800)."
  type        = number
  default     = 3600
}

# ── Vault pass-through (required when enable_vault_secrets = true) ──────────────

variable "postgres_url" {
  description = "Session-mode pooler URL (port 5432) for vault bootstrap. Required when enable_vault_secrets = true."
  type        = string
  sensitive   = true
  default     = ""
}

variable "supabase_ssl_cert" {
  description = "Base64-encoded Supabase CA certificate bundle for pooler connections. Used when enable_vault_secrets = true."
  type        = string
  sensitive   = true
  default     = ""
}

variable "vault_secrets" {
  description = "Desired vault state as name → value map. Only used when enable_vault_secrets = true. Names must be UPPER_SNAKE_CASE."
  type        = map(string)
  sensitive   = true
  default     = {}
}

# ── Vercel pass-through (required when enable_vercel = true) ────────────────────

variable "vercel_project_name" {
  description = "Vercel project name. Required when enable_vercel = true."
  type        = string
  default     = ""
}

variable "vercel_team_id" {
  description = "Vercel team ID. Required when enable_vercel = true."
  type        = string
  default     = ""
}

variable "vercel_github_repo" {
  description = "GitHub repository in 'org/repo' format. Required when enable_vercel = true."
  type        = string
  default     = ""
}

variable "vercel_production_branch" {
  description = "Git branch for the Vercel production environment. Must be an existing branch."
  type        = string
  default     = "main"
}

variable "vercel_root_directory" {
  description = "Root directory within the repository for the Vercel project. Empty string means repository root."
  type        = string
  default     = ""
}

variable "vercel_framework" {
  description = "Framework preset for the Vercel project (e.g. 'nextjs'). Set null for framework-agnostic projects."
  type        = string
  default     = "nextjs"
}

variable "vercel_serverless_region" {
  description = "Vercel serverless function region code."
  type        = string
  default     = "lhr1"
}

variable "vercel_allowed_branches" {
  description = "Git branches that trigger automatic Vercel builds. Must contain at least one branch name."
  type        = list(string)
  default     = ["main"]
}

variable "vercel_domains" {
  description = "Domain assignments for the Vercel project. environment must be one of: qa, uat, production."
  type = list(object({
    domain      = string
    environment = string
  }))
  default = []
}

variable "vercel_qa_env_vars" {
  description = "Vercel environment variables for the QA (preview) environment."
  type = list(object({
    key       = string
    value     = string
    sensitive = optional(bool, false)
  }))
  default = []
}

variable "vercel_uat_env_vars" {
  description = "Vercel environment variables for the UAT custom environment."
  type = list(object({
    key       = string
    value     = string
    sensitive = optional(bool, false)
  }))
  default = []
}

variable "vercel_prod_env_vars" {
  description = "Vercel environment variables for the production environment."
  type = list(object({
    key       = string
    value     = string
    sensitive = optional(bool, false)
  }))
  default = []
}

variable "vercel_shared_env_vars" {
  description = "Vercel environment variables shared across all three environments."
  type = list(object({
    key       = string
    value     = string
    sensitive = optional(bool, false)
  }))
  default = []
}
