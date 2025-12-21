variable "project_id" {
  description = "The ID of the project"
  type        = string
}

variable "region" {
  description = "The region where resources will be created"
  type        = string
  default     = "us-central1"
}

variable "kms_key_name" {
  description = "The name of the KMS key to use for encryption"
  type        = string
  default     = "" # If empty, Google-managed key will be used
}

variable "allowed_members" {
  description = "List of members with read access to the buckets (e.g., ['user:user@example.com', 'group:admins@example.com'])"
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "Number of days to retain logs in the logging bucket"
  type        = number
  default     = 90
}