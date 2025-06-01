variable "monthly_budget_limit" {
  description = "The monthly budget limit in USD"
  type        = number
  default     = 1000
}

variable "alert_threshold" {
  description = "The percentage threshold for budget alerts (0-100)"
  type        = number
  default     = 80
  validation {
    condition     = var.alert_threshold > 0 && var.alert_threshold <= 100
    error_message = "Alert threshold must be between 1 and 100."
  }
}

variable "email_recipients" {
  description = "List of email addresses to receive budget alerts"
  type        = list(string)
  default     = []
  validation {
    condition     = length([for email in var.email_recipients : email if can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))]) == length(var.email_recipients)
    error_message = "All email addresses must be valid."
  }
}

variable "tags" {
  description = "Additional tags to apply to the resources"
  type        = map(string)
  default     = {}
} 