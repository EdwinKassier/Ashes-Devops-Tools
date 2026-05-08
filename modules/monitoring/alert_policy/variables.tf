/**
 * Copyright 2024 Ashes
 *
 * Monitoring Alert Policy Module — Variables
 */

variable "project_id" {
  description = "The GCP project ID in which to create alert policies and notification channels."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project ID."
  }
}

# ── Notification Channels ──────────────────────────────────────────────────────

variable "notification_email_addresses" {
  description = <<-EOT
    List of email addresses to notify when an alert fires. An
    google_monitoring_notification_channel resource is created per address.
    Leave empty to skip email channel creation (use existing channel IDs via
    var.extra_notification_channel_ids instead).
  EOT
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for addr in var.notification_email_addresses :
      can(regex("^[^@]+@[^@]+\\.[^@]+$", addr))
    ])
    error_message = "All entries in notification_email_addresses must be valid email addresses."
  }
}

variable "notification_webhook_urls" {
  description = <<-EOT
    Map of label → HTTPS webhook URL for alert notifications.
    Supports Slack incoming webhooks, PagerDuty, and any generic HTTP endpoint.
    Example: { "slack-ops" = "https://hooks.slack.com/services/T.../B.../xxx" }
    Marked sensitive: URLs contain embedded auth tokens and must not appear in
    plan output or be stored unredacted in CI logs.
  EOT
  type    = map(string)
  default = {}

  validation {
    condition = alltrue([
      for url in values(var.notification_webhook_urls) :
      can(regex("^https://", url))
    ])
    error_message = "All webhook URLs must start with https://."
  }
}

variable "extra_notification_channel_ids" {
  description = "Additional pre-existing notification channel IDs to attach to all alert policies. Format: 'projects/<project>/notificationChannels/<id>'."
  type        = list(string)
  default     = []
}

# ── Alert Policy Toggles ───────────────────────────────────────────────────────

variable "enable_high_cpu_alert" {
  description = "Create an alert policy that fires when CPU utilisation exceeds var.cpu_utilization_threshold."
  type        = bool
  default     = true
}

variable "enable_high_memory_alert" {
  description = "Create an alert policy that fires when memory utilisation exceeds var.memory_utilization_threshold."
  type        = bool
  default     = true
}

variable "enable_error_rate_alert" {
  description = "Create an alert policy that fires when the Cloud Run/GCF 5xx error rate exceeds var.error_rate_threshold_percent."
  type        = bool
  default     = true
}

variable "enable_high_latency_alert" {
  description = "Create an alert policy that fires when Cloud Run P99 request latency exceeds var.latency_p99_threshold_ms."
  type        = bool
  default     = true
}

variable "enable_uptime_alert" {
  description = "Create an uptime check alert policy. Requires var.uptime_check_ids to be set."
  type        = bool
  default     = false
}

variable "enable_log_based_alert" {
  description = "Create a log-based alert that fires on matches to var.log_filter. Useful for security events (e.g., org-policy violations)."
  type        = bool
  default     = false
}

# ── Thresholds ────────────────────────────────────────────────────────────────

variable "cpu_utilization_threshold" {
  description = "Fractional CPU utilisation (0.0–1.0) that triggers the CPU alert (e.g., 0.8 = 80%)."
  type        = number
  default     = 0.8

  validation {
    condition     = var.cpu_utilization_threshold > 0 && var.cpu_utilization_threshold <= 1.0
    error_message = "cpu_utilization_threshold must be in the range (0, 1]."
  }
}

variable "memory_utilization_threshold" {
  description = "Fractional memory utilisation (0.0–1.0) that triggers the memory alert (e.g., 0.85 = 85%)."
  type        = number
  default     = 0.85

  validation {
    condition     = var.memory_utilization_threshold > 0 && var.memory_utilization_threshold <= 1.0
    error_message = "memory_utilization_threshold must be in the range (0, 1]."
  }
}

variable "error_rate_threshold_percent" {
  description = "5xx error rate (requests/second) above which the error-rate alert fires."
  type        = number
  default     = 0.01

  validation {
    condition     = var.error_rate_threshold_percent >= 0
    error_message = "error_rate_threshold_percent must be >= 0."
  }
}

variable "latency_p99_threshold_ms" {
  description = "P99 request latency in milliseconds above which the latency alert fires."
  type        = number
  default     = 2000

  validation {
    condition     = var.latency_p99_threshold_ms > 0
    error_message = "latency_p99_threshold_ms must be > 0."
  }
}

variable "alert_alignment_period" {
  description = "Alignment period (seconds) for time-series aggregation in alert conditions. Minimum 60."
  type        = number
  default     = 60

  validation {
    condition     = var.alert_alignment_period >= 60
    error_message = "alert_alignment_period must be at least 60 seconds."
  }
}

variable "alert_duration" {
  description = "Duration (seconds) a condition must be sustained before the alert fires. Set to 0 to fire immediately on first violation."
  type        = number
  default     = 60

  validation {
    condition     = var.alert_duration >= 0
    error_message = "alert_duration must be >= 0."
  }
}

# ── Uptime Check ──────────────────────────────────────────────────────────────

variable "uptime_check_ids" {
  description = "List of existing uptime check IDs (format: 'projects/<project>/uptimeCheckConfigs/<id>') to create uptime failure alerts for. Required when enable_uptime_alert = true."
  type        = list(string)
  default     = []
}

variable "uptime_check_resource_type" {
  description = <<-EOT
    Monitored resource type used in the uptime check alert filter.
    Use "uptime_url" for HTTP/HTTPS uptime checks (default).
    Use "uptime_tcp" for TCP uptime checks.
    See: https://cloud.google.com/monitoring/api/resources
  EOT
  type        = string
  default     = "uptime_url"

  validation {
    condition     = contains(["uptime_url", "uptime_tcp"], var.uptime_check_resource_type)
    error_message = "uptime_check_resource_type must be \"uptime_url\" (HTTP/HTTPS) or \"uptime_tcp\" (TCP)."
  }
}

# ── Log-Based Alert ───────────────────────────────────────────────────────────

variable "log_filter" {
  description = "Log filter expression for the log-based alert. Required when enable_log_based_alert = true. Example: 'severity=CRITICAL AND protoPayload.methodName=\"SetIamPolicy\"'."
  type        = string
  default     = null
}

variable "log_alert_display_name" {
  description = "Display name for the log-based alert policy."
  type        = string
  default     = "Log-Based Security Alert"
}

# ── Labels & Naming ───────────────────────────────────────────────────────────

variable "alert_display_name_prefix" {
  description = "Prefix applied to all alert policy display names for easy filtering in the console (e.g., 'prod', 'ashes-dev')."
  type        = string
  default     = ""
}

variable "labels" {
  description = "Labels to apply to all notification channel resources."
  type        = map(string)
  default     = {}
}
