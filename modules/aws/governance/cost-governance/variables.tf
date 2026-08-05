# -----------------------------------------------------------------------------
# Gate
# -----------------------------------------------------------------------------

variable "enable_cost_governance" {
  description = "Master gate. When false, no budgets, anomaly monitor/subscription or cost-allocation tags are created (the module composes as a no-op)."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Budgets
# -----------------------------------------------------------------------------

variable "budgets" {
  description = "Monthly COST budgets keyed by budget name. limit_amount is the USD limit; threshold_percent triggers an ACTUAL-spend notification when crossed; emails receive the notification alongside the optional SNS topic."
  type = map(object({
    limit_amount      = string
    threshold_percent = number
    emails            = optional(list(string), [])
  }))
  default = {
    org-monthly = {
      limit_amount      = "1000"
      threshold_percent = 80
    }
  }

  validation {
    condition     = alltrue([for b in values(var.budgets) : b.threshold_percent > 0 && b.threshold_percent <= 100])
    error_message = "Every budget threshold_percent must be in the range (0, 100]."
  }

  validation {
    condition     = alltrue([for b in values(var.budgets) : can(tonumber(b.limit_amount)) && tonumber(b.limit_amount) > 0])
    error_message = "Every budget limit_amount must be a positive numeric string (USD)."
  }
}

variable "notifications_topic_arn" {
  description = "Optional SNS topic ARN that budget notifications are published to, in addition to any per-budget email subscribers. Empty string disables SNS fan-out."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Cost Anomaly Detection
# -----------------------------------------------------------------------------

variable "anomaly_monitor_name" {
  description = "Name of the DIMENSIONAL/SERVICE Cost Anomaly Detection monitor."
  type        = string
  default     = "org-service-monitor"
}

variable "anomaly_subscription_name" {
  description = "Name of the Cost Anomaly Detection subscription wired to the monitor."
  type        = string
  default     = "org-anomaly-sub"
}

variable "anomaly_email" {
  description = "Email address that receives Cost Anomaly Detection alerts."
  type        = string
  default     = "finops@example.com"

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.anomaly_email))
    error_message = "anomaly_email must be a valid email address."
  }
}

variable "anomaly_threshold_usd" {
  description = "Absolute dollar impact (USD) at or above which an anomaly triggers an alert (ANOMALY_TOTAL_IMPACT_ABSOLUTE)."
  type        = number
  default     = 100

  validation {
    condition     = var.anomaly_threshold_usd > 0
    error_message = "anomaly_threshold_usd must be greater than zero."
  }
}

# -----------------------------------------------------------------------------
# Cost-allocation tags
# -----------------------------------------------------------------------------

variable "cost_allocation_tags" {
  description = "Tag keys to activate as cost-allocation tags in Cost Explorer / the Cost & Usage Report. Should mirror the B3 tag-policy keys."
  type        = list(string)
  default     = ["CostCenter", "Environment", "Owner"]

  validation {
    condition     = alltrue([for t in var.cost_allocation_tags : length(trimspace(t)) > 0])
    error_message = "Every cost_allocation_tags entry must be a non-empty tag key."
  }
}
