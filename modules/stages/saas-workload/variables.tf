# ── Supabase variables ─────────────────────────────────────────────────────────

variable "supabase_organization_id" {
  description = "Supabase organisation ID (from dashboard.supabase.com → Organisation Settings). Lowercase alphanumeric, at least 8 characters."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{8,}$", var.supabase_organization_id))
    error_message = "supabase_organization_id must be at least 8 lowercase alphanumeric characters."
  }
}

variable "supabase_project_name" {
  description = "Display name for the Supabase project (3–64 characters)."
  type        = string

  validation {
    condition     = length(var.supabase_project_name) >= 3 && length(var.supabase_project_name) <= 64
    error_message = "supabase_project_name must be between 3 and 64 characters."
  }
}

variable "supabase_database_password" {
  description = "Initial Postgres database password. Minimum 16 characters. Ignored after initial creation."
  type      = string
  sensitive = true

  validation {
    condition     = length(var.supabase_database_password) >= 16
    error_message = "supabase_database_password must be at least 16 characters."
  }
}

variable "supabase_region" {
  description = "Supabase deployment region slug (e.g. 'eu-west-2')."
  type        = string
  default     = "eu-west-2"

  validation {
    condition = contains([
      "us-east-1", "us-west-1", "us-west-2",
      "ap-southeast-1", "ap-northeast-1", "ap-southeast-2",
      "eu-west-1", "eu-west-2", "eu-west-3", "eu-central-1",
      "ca-central-1", "sa-east-1",
    ], var.supabase_region)
    error_message = "supabase_region must be a valid Supabase region slug."
  }
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
  description = "Minimum password length for user accounts (6–100). Default 12 matches the collects reference implementation."
  type        = number
  default     = 12

  validation {
    condition     = var.supabase_password_min_length >= 6 && var.supabase_password_min_length <= 100
    error_message = "supabase_password_min_length must be between 6 and 100."
  }
}

variable "supabase_api_max_rows" {
  description = "Maximum rows returned by a single REST API request (100–100 000)."
  type        = number
  default     = 1000

  validation {
    condition     = var.supabase_api_max_rows >= 100 && var.supabase_api_max_rows <= 100000
    error_message = "supabase_api_max_rows must be between 100 and 100000."
  }
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

  validation {
    condition     = var.supabase_jwt_expiry >= 300 && var.supabase_jwt_expiry <= 604800
    error_message = "supabase_jwt_expiry must be between 300 and 604800."
  }
}

# ── Vault secrets variables ────────────────────────────────────────────────────

variable "enable_vault_secrets" {
  description = "When true, bootstrap and reconcile the Supabase Vault. Requires Node.js >= 18 in the execution environment and var.postgres_url."
  type        = bool
  default     = false
}

variable "postgres_url" {
  description = <<-EOT
    Session-mode pooler URL (port 5432) for vault bootstrap and reconcile.
    Required when enable_vault_secrets = true. Leave empty when disabled.
    Format: postgresql://postgres.<project_ref>:<password>@<host>:5432/postgres
  EOT
  type      = string
  sensitive = true
  default   = ""

  validation {
    condition     = !var.enable_vault_secrets || length(var.postgres_url) > 0
    error_message = "postgres_url is required when enable_vault_secrets = true."
  }
}

variable "supabase_ssl_cert" {
  description = "Base64-encoded Supabase CA certificate bundle. Required for pooler connections when enable_vault_secrets = true."
  type      = string
  sensitive = true
  default   = ""
}

variable "vault_secrets" {
  description = "Desired vault state as name → value map. Only used when enable_vault_secrets = true. Names must be UPPER_SNAKE_CASE."
  type      = map(string)
  sensitive = true
  default   = {}
}

# ── Vercel variables ───────────────────────────────────────────────────────────

variable "enable_vercel" {
  description = "When true, create and configure the Vercel project. Requires var.vercel_team_id and var.vercel_github_repo."
  type        = bool
  default     = false
}

variable "vercel_project_name" {
  description = "Vercel project name. Required when enable_vercel = true."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_vercel || can(regex("^[a-z0-9][a-z0-9-]{0,98}[a-z0-9]$", var.vercel_project_name))
    error_message = "vercel_project_name must be 2–100 lowercase alphanumeric/hyphen characters when enable_vercel = true."
  }
}

variable "vercel_team_id" {
  description = "Vercel team ID. Required when enable_vercel = true."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_vercel || length(var.vercel_team_id) > 0
    error_message = "vercel_team_id is required when enable_vercel = true."
  }
}

variable "vercel_github_repo" {
  description = "GitHub repository in 'org/repo' format. Required when enable_vercel = true."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_vercel || can(regex("^[^/]+/[^/]+$", var.vercel_github_repo))
    error_message = "vercel_github_repo must be in 'org/repo' format when enable_vercel = true."
  }
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

variable "vercel_serverless_region" {
  description = "Vercel serverless function region code."
  type        = string
  default     = "lhr1"

  validation {
    condition = contains([
      "iad1", "sfo1", "pdx1", "sea1", "lhr1", "cdg1", "fra1",
      "bom1", "sin1", "kix1", "cle1", "hnd1", "gru1", "icn1",
      "dub1", "cpt1",
    ], var.vercel_serverless_region)
    error_message = "vercel_serverless_region must be a valid Vercel edge network region."
  }
}

variable "vercel_domains" {
  description = "Domain assignments for the Vercel project. environment must be one of: qa, uat, production."
  type = list(object({
    domain      = string
    environment = string
  }))
  default = []

  validation {
    condition = alltrue([
      for d in var.vercel_domains : contains(["qa", "uat", "production"], d.environment)
    ])
    error_message = "Each domain's environment must be one of: qa, uat, production."
  }
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

variable "vercel_allowed_branches" {
  description = <<-EOT
    Git branches that trigger automatic Vercel builds. Builds on all other
    branches are skipped. Must contain at least one branch name.
    Only used when enable_vercel = true.
  EOT
  type    = list(string)
  default = ["main"]

  validation {
    condition     = length(var.vercel_allowed_branches) >= 1
    error_message = "vercel_allowed_branches must contain at least one branch name."
  }
}

variable "vercel_framework" {
  description = "Framework preset for the Vercel project (e.g. 'nextjs', 'remix', 'astro'). Set null for framework-agnostic projects. Only used when enable_vercel = true."
  type        = string
  default     = "nextjs"
}
