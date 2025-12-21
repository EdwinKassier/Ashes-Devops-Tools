variable "billing_account" {
  description = "The ID of the billing account to create budget for"
  type        = string
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
  description = "Optional webhook endpoint to receive budget alerts"
  type        = string
  default     = ""
}

variable "webhook_service_account" {
  description = "Service account for authenticating webhook requests"
  type        = string
  default     = ""
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
