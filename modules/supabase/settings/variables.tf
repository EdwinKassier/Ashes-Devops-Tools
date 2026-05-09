variable "project_ref" {
  description = "The Supabase project ref — the `id` output from modules/supabase/project. Must be a 20-character lowercase alphanumeric string."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{20}$", var.project_ref))
    error_message = "project_ref must be exactly 20 lowercase alphanumeric characters (the Supabase project ref)."
  }
}

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
  description = "Disable new user sign-ups. Set true for production environments to prevent unwanted registrations."
  type        = bool
  default     = false
}

variable "mailer_autoconfirm" {
  description = "Auto-confirm email addresses on signup without sending a confirmation email. Safe for QA; disable for production."
  type        = bool
  default     = false
}

variable "jwt_expiry" {
  description = "JWT access token expiry in seconds (300–604 800, i.e. 5 minutes to 7 days)."
  type        = number
  default     = 3600

  validation {
    condition     = var.jwt_expiry >= 300 && var.jwt_expiry <= 604800
    error_message = "jwt_expiry must be between 300 (5 min) and 604800 (7 days)."
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
