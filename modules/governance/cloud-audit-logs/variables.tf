variable "project_id" {
  description = "The ID of the project where the Cloud Audit Logs will be configured"
  type        = string
}

variable "bucket_location" {
  description = "The location of the bucket that will store audit logs"
  type        = string
  default     = "US"
}

variable "log_retention_days" {
  description = "The number of days to retain audit logs in the storage bucket"
  type        = number
  default     = 365
}

variable "force_destroy_bucket" {
  description = "When deleting the bucket, automatically delete all objects"
  type        = bool
  default     = false
}

variable "kms_key_name" {
  description = "The KMS key name to encrypt the audit logs bucket (optional)"
  type        = string
  default     = null
}
