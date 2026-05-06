variable "billing_account" {
  description = "The GCP billing account ID in format XXXXXX-XXXXXX-XXXXXX"
  type        = string

  validation {
    condition     = can(regex("^[A-Z0-9]{6}-[A-Z0-9]{6}-[A-Z0-9]{6}$", var.billing_account))
    error_message = "billing_account must be a valid GCP billing account ID in format XXXXXX-XXXXXX-XXXXXX."
  }
}

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
}

variable "project_name" {
  description = "The name prefix for resources"
  type        = string
}

variable "projects" {
  description = "List of project IDs to monitor in the budget"
  type        = list(string)
  default     = []
}

variable "region" {
  description = "The region where Cloud Function will be deployed"
  type        = string
  default     = "us-central1"
}

variable "kms_key_name" {
  description = "Optional customer-managed KMS key used to encrypt the budget alert Pub/Sub topic"
  type        = string
  default     = null
}

variable "monthly_budget_limit" {
  description = "The monthly budget limit in the specified currency"
  type        = number

  validation {
    condition     = var.monthly_budget_limit > 0
    error_message = "Monthly budget limit must be greater than 0"
  }
}

variable "currency_code" {
  description = "The currency code for the budget (e.g., USD, EUR, GBP)"
  type        = string
  default     = "USD"

  validation {
    condition     = length(var.currency_code) == 3
    error_message = "Currency code must be a 3-letter ISO 4217 code"
  }
}

variable "alert_threshold_percent" {
  description = "The percentage threshold for the first alert (0.5 = 50%)"
  type        = number
  default     = 0.5

  validation {
    condition     = var.alert_threshold_percent > 0 && var.alert_threshold_percent <= 1
    error_message = "Alert threshold must be between 0 and 1"
  }
}

variable "label_filters" {
  description = "Map of label keys to values for filtering budget scope (single value per key)"
  type        = map(string)
  default     = {}
}

variable "service_filters" {
  description = "List of GCP service IDs to include in budget (empty = all services)"
  type        = list(string)
  default     = []
}

variable "notification_channels" {
  description = "List of monitoring notification channel IDs"
  type        = list(string)
  default     = []
}

variable "webhook_endpoint" {
  description = "Optional webhook endpoint URL to receive budget alerts (must start with https://)"
  type        = string
  default     = ""

  validation {
    condition     = var.webhook_endpoint == "" || can(regex("^https://", var.webhook_endpoint))
    error_message = "webhook_endpoint must be empty or a valid HTTPS URL starting with 'https://'."
  }
}

variable "webhook_service_account" {
  description = "Service account email for authenticating webhook requests (format: name@project.iam.gserviceaccount.com)"
  type        = string
  default     = ""

  validation {
    condition     = var.webhook_service_account == "" || can(regex("^[^@]+@[^@]+\\.[^@]+$", var.webhook_service_account))
    error_message = "webhook_service_account must be empty or a valid service account email address."
  }
}

variable "enable_email_notifications" {
  description = "Enable email notifications via Cloud Function"
  type        = bool
  default     = false
}

variable "functions_bucket" {
  description = "Cloud Storage bucket containing the Cloud Function source code"
  type        = string
  default     = ""
}

variable "function_source_object" {
  description = "Cloud Storage object name for the Cloud Function source"
  type        = string
  default     = ""
}

variable "sendgrid_api_key_secret_id" {
  description = "Secret Manager secret ID for SendGrid API key (recommended to use Secret Manager)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "email_recipients" {
  description = "List of email addresses to receive budget alerts"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for email in var.email_recipients :
      can(regex("^[^@]+@[^@]+\\.[^@]+$", email))
    ])
    error_message = "All email_recipients must be valid email addresses."
  }
}

variable "pubsub_service_account" {
  description = "Service account used by Pub/Sub to invoke Cloud Function"
  type        = string
  default     = "service-PROJECT_NUMBER@gcp-sa-pubsub.iam.gserviceaccount.com"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
