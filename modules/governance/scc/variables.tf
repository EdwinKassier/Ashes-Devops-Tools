variable "org_id" {
  description = "The organization ID where SCC is enabled"
  type        = string
}

variable "project_id" {
  description = "The project ID where the Pub/Sub topic will be created"
  type        = string
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
