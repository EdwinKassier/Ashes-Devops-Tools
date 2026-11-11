/**
 * Copyright 2023 Ashes
 *
 * Cloud SQL (PostgreSQL) Module - Variables
 */

variable "project_id" {
  description = "The ID of the project where the instance will be created"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be 6-30 characters, start with a lowercase letter, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "region" {
  description = "The GCP region to host the instance in (e.g. europe-west1)"
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a valid GCP region (e.g. \"europe-west1\")."
  }
}

variable "name" {
  description = "Name of the Cloud SQL instance"
  type        = string

  validation {
    condition     = can(regex("^[a-z][-a-z0-9]{0,96}[a-z0-9]$", var.name))
    error_message = "name must start with a lowercase letter, end with a letter or digit, and contain only lowercase letters, digits, and hyphens (max 98 characters)."
  }
}

variable "database_version" {
  description = "The PostgreSQL engine version (e.g. POSTGRES_16)"
  type        = string
  default     = "POSTGRES_16"

  validation {
    condition     = can(regex("^POSTGRES_", var.database_version))
    error_message = "database_version must be a PostgreSQL version (prefixed with 'POSTGRES_'); this module only manages PostgreSQL instances."
  }
}

variable "tier" {
  description = "The machine type / tier for the instance (e.g. db-custom-1-3840)"
  type        = string
  default     = "db-custom-1-3840"

  validation {
    condition     = can(regex("^db-", var.tier))
    error_message = "tier must be a valid Cloud SQL tier (prefixed with 'db-', e.g. \"db-custom-1-3840\")."
  }
}

variable "edition" {
  description = "Cloud SQL edition. ENTERPRISE (default) matches the `db-custom-*` tiers; ENTERPRISE_PLUS needs a `db-perf-optimized-*` tier. Set explicitly because PostgreSQL 16+ otherwise defaults to ENTERPRISE_PLUS and the default tier fails to create."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "ENTERPRISE_PLUS"], var.edition)
    error_message = "edition must be ENTERPRISE or ENTERPRISE_PLUS."
  }

  validation {
    condition     = var.edition != "ENTERPRISE_PLUS" || can(regex("^db-perf-optimized-", var.tier))
    error_message = "edition = ENTERPRISE_PLUS requires a db-perf-optimized-* tier."
  }
}

# -----------------------------------------------------------------------------
# PRIVATE NETWORKING (secure by default — no public IP)
# -----------------------------------------------------------------------------

variable "private_network" {
  description = "The self_link of the Shared VPC network to peer the instance into via Private Service Access. The instance is reachable on a private IP only."
  type        = string
}

# -----------------------------------------------------------------------------
# HIGH AVAILABILITY
# -----------------------------------------------------------------------------

variable "enable_high_availability" {
  description = "When true the instance runs REGIONAL (synchronous standby, automatic failover); otherwise ZONAL."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# BACKUPS
# -----------------------------------------------------------------------------

variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery (continuous WAL archiving). Requires backups, which this module always enables."
  type        = bool
  default     = true
}

variable "backup_start_time" {
  description = "Daily automated-backup start time in 24h HH:MM UTC"
  type        = string
  default     = "03:00"

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_start_time))
    error_message = "backup_start_time must be a 24h HH:MM time (e.g. \"03:00\")."
  }
}

variable "backup_location" {
  description = "Location of the automated backups: a region (e.g. europe-west2) or a multi-region (eu, us, asia). Pick a region other than the instance's to survive a regional outage. Null (default) = Cloud SQL's default, the multi-region nearest the instance."
  type        = string
  default     = null

  validation {
    condition     = var.backup_location == null || can(regex("^([a-z]+-[a-z]+[0-9]+|us|eu|asia)$", coalesce(var.backup_location, "-")))
    error_message = "backup_location must be a GCP region (e.g. europe-west2) or a multi-region (us, eu, asia)."
  }
}

variable "transaction_log_retention_days" {
  description = "Number of days of transaction (WAL) logs to retain for point-in-time recovery"
  type        = number
  default     = 7

  validation {
    condition     = var.transaction_log_retention_days >= 1 && var.transaction_log_retention_days <= 35
    error_message = "transaction_log_retention_days must be between 1 and 35."
  }
}

# -----------------------------------------------------------------------------
# SECURITY: IAM AUTH + CMEK
# -----------------------------------------------------------------------------

variable "enable_iam_authentication" {
  description = "Enable Cloud SQL IAM database authentication (sets the cloudsql.iam_authentication flag on)."
  type        = bool
  default     = true
}

variable "encryption_key_name" {
  description = "Optional CMEK: the self_link of a Cloud KMS CryptoKey used to encrypt the instance. Leave null to use Google-managed encryption."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# DATABASE FLAGS
# -----------------------------------------------------------------------------

variable "database_flags" {
  description = "Additional database flags to set on the instance. The cloudsql.iam_authentication flag is managed by enable_iam_authentication and must not be duplicated here."
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

# -----------------------------------------------------------------------------
# MAINTENANCE WINDOW
# -----------------------------------------------------------------------------

variable "maintenance_window_day" {
  description = "Day of week (1 = Monday … 7 = Sunday) for the maintenance window"
  type        = number
  default     = 7

  validation {
    condition     = var.maintenance_window_day >= 1 && var.maintenance_window_day <= 7
    error_message = "maintenance_window_day must be between 1 (Monday) and 7 (Sunday)."
  }
}

variable "maintenance_window_hour" {
  description = "Hour of day (0-23, UTC) for the maintenance window"
  type        = number
  default     = 3

  validation {
    condition     = var.maintenance_window_hour >= 0 && var.maintenance_window_hour <= 23
    error_message = "maintenance_window_hour must be between 0 and 23."
  }
}

variable "maintenance_window_update_track" {
  description = "Maintenance release track: 'canary' (earlier) or 'stable' (later)"
  type        = string
  default     = "stable"

  validation {
    condition     = contains(["canary", "stable", "week5"], var.maintenance_window_update_track)
    error_message = "maintenance_window_update_track must be one of 'canary', 'stable', or 'week5'."
  }
}

# -----------------------------------------------------------------------------
# DATABASES & USERS
# -----------------------------------------------------------------------------

variable "databases" {
  description = "List of logical database names to create on the instance"
  type        = list(string)
  default     = []
}

variable "users" {
  description = <<-EOT
    List of database users to create. For built-in (password) users set `password`
    (prefer IAM auth instead). For IAM users set `type = "CLOUD_IAM_USER"` (or
    "CLOUD_IAM_SERVICE_ACCOUNT") and omit the password. Passwords are written with the
    write-only password_wo argument, so they never land in plan or state; increment
    `password_version` to rotate. The variable is still marked sensitive.

    To keep a password out of the module input entirely, set
    `ephemeral_password = true` (and omit `password`): the password is then read
    from the ephemeral var.user_passwords[name]. The flag lives here because the
    user set and the write-only version must stay non-ephemeral.
  EOT
  type = list(object({
    name               = string
    password           = optional(string)
    password_version   = optional(number, 1)
    type               = optional(string, "BUILT_IN")
    ephemeral_password = optional(bool, false)
  }))
  default   = []
  sensitive = true

  validation {
    condition     = alltrue([for u in var.users : !(u.ephemeral_password && u.password != null)])
    error_message = "a user with ephemeral_password = true must not also set password (it is read from user_passwords)."
  }

  validation {
    condition     = alltrue([for u in var.users : !u.ephemeral_password || u.type == "BUILT_IN"])
    error_message = "ephemeral_password = true is only valid for BUILT_IN users (IAM users carry no password)."
  }
}

variable "user_passwords" {
  description = "Ephemeral built-in user passwords as user name => password, for users declared in var.users with ephemeral_password = true. Never stored in plan or state; feed it from an ephemeral resource (e.g. google_secret_manager_secret_version) or an ephemeral root variable. Every key must name such a user."
  type        = map(string)
  default     = {}
  sensitive   = true
  ephemeral   = true

  validation {
    condition = alltrue([
      for name in keys(var.user_passwords) :
      contains([for u in var.users : u.name if u.ephemeral_password], name)
    ])
    error_message = "every key in user_passwords must name a user in var.users with ephemeral_password = true."
  }

  validation {
    condition = alltrue([
      for u in var.users : contains(keys(var.user_passwords), u.name) if u.ephemeral_password
    ])
    error_message = "every user with ephemeral_password = true needs an entry in user_passwords."
  }
}

# -----------------------------------------------------------------------------
# DELETION PROTECTION
# -----------------------------------------------------------------------------

variable "enable_deletion_protection" {
  description = <<-EOT
    Prevent accidental destruction of the instance.

    When true, the instance's own deletion_protection API attribute is set and a
    terraform_data guard resource is created with prevent_destroy = true. The
    guard is replaced whenever the instance would be replaced, so Terraform
    refuses any plan that destroys or replaces the instance. Setting this to
    false while the guard exists is also refused. To intentionally destroy or
    replace a protected instance, first run:
      terraform state rm 'module.<name>.terraform_data.deletion_protection_guard[0]'
    then set this to false and apply.
  EOT
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# LABELS
# -----------------------------------------------------------------------------

variable "labels" {
  description = "A map of key/value labels to apply to the instance"
  type        = map(string)
  default     = {}
}

variable "enable_secure_log_flags" {
  description = "Apply a secure-by-default PostgreSQL logging flag set (log_checkpoints/connections/disconnections/lock_waits, log_min_messages=error, log_statement=ddl). Default true. Caller flags in database_flags override these per name. Set false to manage all flags yourself."
  type        = bool
  default     = true
}
