# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------

variable "project_id" {
  description = "GCP project ID where the dashboard will be created"
  type        = string
}

# -----------------------------------------------------------------------------
# Dashboard Configuration
# -----------------------------------------------------------------------------

variable "dashboard_display_name" {
  description = "Display name for the monitoring dashboard"
  type        = string
  default     = "Unified Compute Dashboard"
}

# -----------------------------------------------------------------------------
# Scorecard Thresholds
# -----------------------------------------------------------------------------

variable "latency_threshold_ms" {
  description = "P99 latency threshold in milliseconds for scorecard warning indicator"
  type        = number
  default     = 1000

  validation {
    condition     = var.latency_threshold_ms > 0
    error_message = "Latency threshold must be a positive number."
  }
}

variable "error_rate_threshold_percent" {
  description = "Error rate threshold percentage for scorecard warning indicator"
  type        = number
  default     = 1.0

  validation {
    condition     = var.error_rate_threshold_percent >= 0 && var.error_rate_threshold_percent <= 100
    error_message = "Error rate threshold must be between 0 and 100."
  }
}

# -----------------------------------------------------------------------------
# Metric Inclusion Options
# -----------------------------------------------------------------------------

variable "include_gen1_functions" {
  description = "Include Gen1 Cloud Functions metrics (cloudfunctions.googleapis.com). Set to false if only using Gen2/Cloud Run functions."
  type        = bool
  default     = true
}
