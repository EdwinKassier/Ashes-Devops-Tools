variable "landing_zone_config_path" {
  description = "Path to the single-source landing-zone config (YAML; schema config/landing-zone.example.yaml), absolute or relative to this root. Null = ../../config/landing-zone.yaml; \"\" disables the lookup. Read only if the file exists; explicit variables win over its values."
  type        = string
  default     = null
}

# ── Terraform Cloud / cross-cloud wiring ────────────────

variable "tfc_organization" {
  description = "Terraform Cloud organization name. Required only when cross_cloud_references is non-empty (it reads upstream workspace state). Leave null for a standalone SaaS deployment. Null = org.tfc.organization from config/landing-zone.yaml."
  type        = string
  default     = null
}

variable "cross_cloud_references" {
  description = <<-EOT
    Opt-in frontend-URL seam. Inject outputs from AWS/GCP workspaces into the
    Vercel app as shared environment variables, resolved from remote state at plan
    time (no AWS or GCP credentials needed, only tfc_organization). Keyed by a
    label; each entry names the upstream workspace, the output to read, and the
    Vercel env var to set. Default empty: no cross-cloud reads, and this root stays
    standalone.

      workspace_name  upstream TFC workspace, e.g. "gcp-workload-prod".
      output_key      the output to read from that workspace, e.g. "api_endpoint".
      vercel_env_key  the Vercel env var name to set, e.g. "NEXT_PUBLIC_API_URL".
      sensitive       mark the resulting Vercel env var sensitive (default true, write-only in Vercel; set false only for values that must be readable in the dashboard).
  EOT
  type = map(object({
    workspace_name = string
    output_key     = string
    vercel_env_key = string
    sensitive      = optional(bool, true)
  }))
  default = {}

  validation {
    condition = alltrue([
      for r in values(var.cross_cloud_references) :
      length(trimspace(r.workspace_name)) > 0 && length(trimspace(r.output_key)) > 0 && can(regex("^[A-Za-z_][A-Za-z0-9_]*$", r.vercel_env_key))
    ])
    error_message = "Each cross_cloud_references entry needs a non-empty workspace_name and output_key, and a vercel_env_key that is a valid environment variable name."
  }

  validation {
    condition     = length(var.cross_cloud_references) == 0 || coalesce(var.tfc_organization, local.cfg.tfc_organization, "!unset") != "!unset"
    error_message = "cross_cloud_references requires tfc_organization to be set (it reads upstream workspace state)."
  }
}

# ── Feature flags ─────────────────────────────────────────────────────────────

variable "enable_supabase" {
  description = "Provision the Supabase project. Set false for a Vercel-only deployment — the Supabase inputs may then be left at their defaults. Null = saas.supabase from config/landing-zone.yaml, else true."
  type        = bool
  default     = null
}

variable "enable_vercel" {
  description = "Provision the Vercel project. Set false for a Supabase-only deployment — the Vercel inputs may then be left at their defaults. Null = saas.vercel from config/landing-zone.yaml, else true."
  type        = bool
  default     = null
}

variable "enable_vault_secrets" {
  description = "Bootstrap and reconcile the Supabase Vault. Requires Node.js >= 18 in the execution environment and var.postgres_url. Default false."
  type        = bool
  default     = false
}

# ── Supabase pass-through (required when enable_supabase = true) ────────────────

variable "supabase_organization_id" {
  description = "Supabase organisation ID. Required when enable_supabase = true; at least 8 lowercase alphanumeric characters. Empty = saas.stacks.<stack>.supabase.organization_id, else saas.defaults.supabase.organization_id, from config/landing-zone.yaml."
  type        = string
  default     = ""
}

variable "supabase_project_name" {
  description = "Display name for the Supabase project (3–64 chars). Required when enable_supabase = true. Empty = saas.stacks.<stack>.supabase.project_name from config/landing-zone.yaml."
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
  description = "Supabase deployment region slug (e.g. 'eu-west-2'). Null = saas.stacks.<stack>.supabase.region, else saas.defaults.supabase.region, else eu-west-2."
  type        = string
  default     = null
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

  validation {
    # iac_vault holds the vault-secrets SECURITY DEFINER helpers; exposing it via
    # PostgREST would let API keys reach them. vault holds the encrypted secrets.
    condition = length(setintersection(
      toset([for s in split(",", var.supabase_db_schema) : lower(trimspace(s))]),
      toset(["iac_vault", "vault"]),
    )) == 0
    error_message = "supabase_db_schema must not expose the iac_vault or vault schemas via the REST API (they hold the Vault secrets and their privileged helpers)."
  }
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
  description = "Vercel project name. Required when enable_vercel = true. Empty = saas.stacks.<stack>.vercel.project_name from config/landing-zone.yaml."
  type        = string
  default     = ""
}

variable "vercel_team_id" {
  description = "Vercel team ID. Required when enable_vercel = true. Empty = saas.stacks.<stack>.vercel.team_id, else saas.defaults.vercel.team_id."
  type        = string
  default     = ""
}

variable "vercel_github_repo" {
  description = "GitHub repository in 'org/repo' format. Required when enable_vercel = true. Empty = saas.stacks.<stack>.vercel.github_repo from config/landing-zone.yaml."
  type        = string
  default     = ""
}

variable "vercel_production_branch" {
  description = "Git branch for the Vercel production environment. Must be an existing branch. Null = saas.stacks.<stack>.vercel.production_branch, else main."
  type        = string
  default     = null
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
  description = "Vercel environment variables for the QA (preview) environment. Each entry's sensitive defaults to true (secure by default)."
  type = list(object({
    key       = string
    value     = string
    sensitive = optional(bool, true)
  }))
  default = []
}

variable "vercel_uat_env_vars" {
  description = "Vercel environment variables for the UAT custom environment. Each entry's sensitive defaults to true (secure by default)."
  type = list(object({
    key       = string
    value     = string
    sensitive = optional(bool, true)
  }))
  default = []
}

variable "vercel_prod_env_vars" {
  description = "Vercel environment variables for the production environment. Each entry's sensitive defaults to true (secure by default)."
  type = list(object({
    key       = string
    value     = string
    sensitive = optional(bool, true)
  }))
  default = []
}

variable "vercel_shared_env_vars" {
  description = "Vercel environment variables shared across all three environments. Each entry's sensitive defaults to true (secure by default)."
  type = list(object({
    key       = string
    value     = string
    sensitive = optional(bool, true)
  }))
  default = []
}

variable "stack" {
  description = "SaaS stack key in saas.stacks (config/landing-zone.yaml) this workspace deploys. Null = the workspace name without the saas- prefix (tfc-admin sets it explicitly on every saas-<name> workspace)."
  type        = string
  default     = null
}
