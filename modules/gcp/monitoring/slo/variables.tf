variable "project_id" {
  description = "Project that owns the SLO and the monitored service."
  type        = string
}

variable "service_id" {
  description = "ID of the monitored service the SLO is attached to (e.g. the google_monitoring_service for a Cloud Run service)."
  type        = string
}

variable "slo_id" {
  description = "Stable ID for this SLO within the service."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.slo_id))
    error_message = "slo_id must be a lowercase DNS-style name."
  }
}

variable "display_name" {
  description = "Human-readable SLO name, e.g. 'API 99.9% availability'."
  type        = string
}

variable "sli_type" {
  description = "Which basic SLI to measure: 'availability' or 'latency'."
  type        = string
  default     = "availability"

  validation {
    condition     = contains(["availability", "latency"], var.sli_type)
    error_message = "sli_type must be 'availability' or 'latency'."
  }
}

variable "latency_threshold" {
  description = "Latency threshold (e.g. '1s') for a latency SLI. Required when sli_type = latency."
  type        = string
  default     = "1s"
}

variable "goal" {
  description = "SLO target as a fraction, e.g. 0.999 for 99.9%."
  type        = number
  default     = 0.99

  validation {
    condition     = var.goal > 0 && var.goal < 1
    error_message = "goal must be a fraction strictly between 0 and 1 (e.g. 0.999)."
  }
}

variable "rolling_period_days" {
  description = "Rolling compliance window in days (e.g. 28)."
  type        = number
  default     = 28
}

variable "enable_burn_rate_alert" {
  description = "Create an alert policy on fast error-budget burn. Default false; set notification_channels when enabling."
  type        = bool
  default     = false
}

variable "burn_rate_threshold" {
  description = "Burn-rate multiple that triggers the alert (e.g. 10 = burning 10x the sustainable rate)."
  type        = number
  default     = 10
}

variable "burn_rate_lookback" {
  description = "Lookback window for the burn-rate calculation, e.g. '3600s'."
  type        = string
  default     = "3600s"
}

variable "notification_channels" {
  description = "Monitoring notification channel IDs for the burn-rate alert."
  type        = list(string)
  default     = []
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
