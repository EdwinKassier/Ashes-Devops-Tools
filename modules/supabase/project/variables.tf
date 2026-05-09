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
    ⚠️  After creation this value is IGNORED on subsequent applies —
    lifecycle.ignore_changes is set because the Supabase Management API
    does not support rotating the password programmatically. Manage
    password rotation directly in the Supabase dashboard.
  EOT
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.database_password) >= 16
    error_message = "database_password must be at least 16 characters."
  }
}

variable "region" {
  description = <<-EOT
    Supabase deployment region slug. See
    https://supabase.com/docs/guides/platform/regions for the full list.
  EOT
  type        = string
  default     = "eu-west-2"

  validation {
    condition = contains([
      "us-east-1", "us-west-1", "us-west-2",
      "ap-southeast-1", "ap-northeast-1", "ap-southeast-2",
      "eu-west-1", "eu-west-2", "eu-west-3", "eu-central-1",
      "ca-central-1", "sa-east-1",
    ], var.region)
    error_message = "region must be a valid Supabase region slug (e.g. 'eu-west-2')."
  }
}
