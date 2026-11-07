variable "org_id" {
  description = "Numeric GCP Organization ID where SCC is enabled (digits only, without 'organizations/' prefix)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.org_id))
    error_message = "org_id must be a numeric organization ID (digits only, without 'organizations/' prefix)."
  }
}

variable "project_id" {
  description = "The GCP project ID where the Pub/Sub topic will be created (lowercase letters, digits, hyphens; 6–30 characters; starts with a letter)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project ID: 6–30 characters, start with a lowercase letter, contain only lowercase letters, digits, and hyphens, and not end with a hyphen."
  }
}

variable "kms_key_name" {
  description = "Optional customer-managed KMS key used to encrypt SCC notification topics"
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_name == null || can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.kms_key_name))
    error_message = "kms_key_name must be a valid KMS key resource name: projects/<project>/locations/<location>/keyRings/<ring>/cryptoKeys/<key>."
  }
}

# =============================================================================
# LEGACY SINGLE CONFIG (Backward Compatibility)
# =============================================================================

variable "pubsub_topic_name" {
  description = "Name of the Pub/Sub topic for SCC notifications (legacy single config)"
  type        = string
  default     = "scc-notifications"
}

variable "config_id" {
  description = "ID for the notification config (legacy single config)"
  type        = string
  default     = "scc-notification-config"
}

variable "description" {
  description = "Description of the notification config (legacy single config)"
  type        = string
  default     = "SCC notifications for active findings"
}

variable "filter" {
  description = "The filter string to trigger notifications (legacy single config)"
  type        = string
  default     = "state=\"ACTIVE\""
}

# =============================================================================
# ADVANCED: MULTIPLE NOTIFICATION CONFIGS (Severity-Based Routing)
# =============================================================================

variable "notification_configs" {
  description = <<-EOF
    Map of notification configurations for severity-based routing.
    When provided, this takes precedence over the legacy single config variables.

    Example:
    notification_configs = {
      "critical-high" = {
        pubsub_topic_name = "scc-critical-findings"
        description       = "Critical and High severity findings"
        filter            = "state=\"ACTIVE\" AND (severity=\"CRITICAL\" OR severity=\"HIGH\")"
      }
      "medium-low" = {
        pubsub_topic_name = "scc-medium-findings"
        description       = "Medium and Low severity findings"
        filter            = "state=\"ACTIVE\" AND (severity=\"MEDIUM\" OR severity=\"LOW\")"
      }
    }
  EOF
  type = map(object({
    pubsub_topic_name = string
    description       = optional(string, "SCC notification configuration")
    filter            = string
  }))
  default = {}
}

variable "labels" {
  description = "Labels applied to every labelable resource this module creates (merged with the provider default_labels; resource-specific labels win)."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "labels keys/values must be lowercase GCP label syntax (keys start with a letter, <= 63 chars)."
  }
}

variable "scc_api_version" {
  description = "SCC API generation for notification and mute configs: v1 (default, unchanged), both (create the v2 twins next to v1 to verify), or v2 (flip; the v1 configs are destroyed). v1 and v2 cannot see each other's configs; see docs/runbooks/scc-v2-migration.md."
  type        = string
  default     = "v1"
  nullable    = false

  validation {
    condition     = contains(["v1", "both", "v2"], var.scc_api_version)
    error_message = "scc_api_version must be one of: v1, both, v2."
  }
}

variable "scc_location" {
  description = "Location of the SCC v2 configs (global or a data-residency region). Ignored for v1."
  type        = string
  default     = "global"
  nullable    = false
}

variable "mute_configs" {
  description = "Map of SCC mute configs keyed by mute_config_id (created with the API generation(s) selected by scc_api_version). type is STATIC or DYNAMIC."
  type = map(object({
    description = optional(string, "Managed by Terraform")
    filter      = string
    type        = optional(string, "STATIC")
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k, v in var.mute_configs : contains(["STATIC", "DYNAMIC"], v.type)])
    error_message = "mute_configs[*].type must be STATIC or DYNAMIC."
  }
}
