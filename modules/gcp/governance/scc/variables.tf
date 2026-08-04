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
