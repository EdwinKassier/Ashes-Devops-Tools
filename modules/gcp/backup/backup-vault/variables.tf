/**
 * Backup Vault Module - Variables
 */

variable "project_id" {
  description = "Project that holds the backup vault and its backup plan (the environment host project)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be 6-30 characters, start with a lowercase letter, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "location" {
  description = "Region of the vault and the backup plan. It must be the region of the Cloud SQL instances: Backup and DR needs the plan in the instance region."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.location))
    error_message = "location must be a GCP region (e.g. \"europe-west2\"), not a multi-region."
  }
}

variable "vault_id" {
  description = "ID of the backup vault. It also prefixes the backup plan and association IDs."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,50}$", var.vault_id))
    error_message = "vault_id must start with a lowercase letter and contain only lowercase letters, digits and hyphens (at most 51 characters, so the derived plan ID fits)."
  }
}

variable "enforced_retention_days" {
  description = "Minimum enforced retention of the vault, in days. Every backup in the vault is immutable for this long, and the Cloud SQL plan keeps backups exactly this long. You can raise or lower it until lock_effective_time; after that you can only raise it. Cloud SQL accepts at most 3653 days (10 years)."
  type        = number
  default     = 35
  nullable    = false

  validation {
    condition     = var.enforced_retention_days >= 1 && var.enforced_retention_days <= 3653 && floor(var.enforced_retention_days) == var.enforced_retention_days
    error_message = "enforced_retention_days must be a whole number of days from 1 to 3653 (Cloud SQL's 10-year limit for a vault)."
  }
}

variable "lock_effective_time" {
  description = "IRREVERSIBLE. RFC 3339 UTC time (e.g. 2027-01-01T00:00:00Z) after which the vault's minimum enforced retention is locked: nobody can lower it again. Null (default) = no lock."
  type        = string
  default     = null

  validation {
    condition     = var.lock_effective_time == null || can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$", coalesce(var.lock_effective_time, "-")))
    error_message = "lock_effective_time must be an RFC 3339 UTC time such as 2027-01-01T00:00:00Z."
  }
}

variable "cloud_sql_instances" {
  description = "Cloud SQL instances to protect: key => projects/<project>/instances/<instance>. Every instance must be in location. Empty (default) = a vault with no plan."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for k, v in var.cloud_sql_instances : can(regex("^[a-z][a-z0-9-]{0,40}$", k)) && can(regex("^projects/[a-z][a-z0-9-]+/instances/[a-z][a-z0-9-]+$", v))])
    error_message = "cloud_sql_instances keys must be short lowercase IDs, and each value must be projects/<project>/instances/<instance>."
  }
}

variable "cloud_sql_source_projects" {
  description = "Projects other than project_id that hold the cloud_sql_instances: key => project ID. The vault's service agent gets roles/backupdr.cloudSqlOperator in each, and the Backup and DR API is enabled there. Keys must be known at plan time."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for k, v in var.cloud_sql_source_projects : k != "vault" && can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", v))])
    error_message = "cloud_sql_source_projects values must be GCP project IDs, and \"vault\" is a reserved key."
  }
}

variable "backup_window_start_hour" {
  description = "UTC hour (0-20) at which the daily four-hour backup window opens."
  type        = number
  default     = 2
  nullable    = false

  validation {
    condition     = var.backup_window_start_hour >= 0 && var.backup_window_start_hour <= 20 && floor(var.backup_window_start_hour) == var.backup_window_start_hour
    error_message = "backup_window_start_hour must be a whole hour from 0 to 20."
  }
}

variable "labels" {
  description = "Labels for the vault and the backup plan."
  type        = map(string)
  default     = {}
}
