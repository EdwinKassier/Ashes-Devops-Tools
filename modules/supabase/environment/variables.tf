# ── Project variables (forwarded to modules/supabase/project) ─────────────────

variable "organization_id" {
  description = <<-EOT
    Supabase organisation ID. Find this in the Supabase dashboard under
    Organisation Settings → General → Organisation ID.
    Format: lowercase alphanumeric, at least 8 characters.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{8,}$", var.organization_id))
    error_message = "organization_id must be at least 8 lowercase alphanumeric characters."
  }
}

variable "project_name" {
  description = "Display name for the Supabase project (3–64 characters)."
  type        = string

  validation {
    condition     = length(var.project_name) >= 3 && length(var.project_name) <= 64
    error_message = "project_name must be between 3 and 64 characters."
  }
}

variable "database_password" {
  description = <<-EOT
    Initial Postgres database password. Minimum 16 characters.
    Ignored after initial project creation — see modules/supabase/project for details.
  EOT
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.database_password) >= 16
    error_message = "database_password must be at least 16 characters."
  }
}

variable "region" {
  description = "Supabase deployment region slug (e.g. 'eu-west-2'). See https://supabase.com/docs/guides/platform/regions."
  type        = string
  default     = "eu-west-2"

  validation {
    condition = contains([
      "us-east-1", "us-west-1", "us-west-2",
      "ap-southeast-1", "ap-northeast-1", "ap-southeast-2",
      "eu-west-1", "eu-west-2", "eu-west-3", "eu-central-1",
      "ca-central-1", "sa-east-1",
    ], var.region)
    error_message = "region must be a valid Supabase region slug."
  }
}

# ── Settings variables (forwarded to modules/supabase/settings) ───────────────

variable "api_max_rows" {
  description = "Maximum rows returned by a single REST API request (100–100 000)."
  type        = number
  default     = 1000

  validation {
    condition     = var.api_max_rows >= 100 && var.api_max_rows <= 100000
    error_message = "api_max_rows must be between 100 and 100000."
  }
}

variable "db_schema" {
  description = "Comma-separated list of Postgres schemas exposed via the REST API."
  type        = string
  default     = "public,graphql_public"
}

variable "db_extra_search_path" {
  description = "Comma-separated list of schemas appended to the Postgres search_path."
  type        = string
  default     = "public,extensions"
}

variable "disable_signup" {
  description = "Disable new user sign-ups. Set true for production environments."
  type        = bool
  default     = false
}

variable "mailer_autoconfirm" {
  description = "Auto-confirm email addresses on signup without sending a confirmation email. QA only; disable in production."
  type        = bool
  default     = false
}

variable "jwt_expiry" {
  description = "JWT access token expiry in seconds (300–604 800)."
  type        = number
  default     = 3600

  validation {
    condition     = var.jwt_expiry >= 300 && var.jwt_expiry <= 604800
    error_message = "jwt_expiry must be between 300 and 604800."
  }
}

variable "password_min_length" {
  description = "Minimum password length for user accounts (6–100). Default 12 matches the collects reference implementation."
  type        = number
  default     = 12

  validation {
    condition     = var.password_min_length >= 6 && var.password_min_length <= 100
    error_message = "password_min_length must be between 6 and 100."
  }
}
