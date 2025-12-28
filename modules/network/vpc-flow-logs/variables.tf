/**
 * Copyright 2023 Ashes
 *
 * VPC Flow Logs Export Module - Variables
 */

# -----------------------------------------------------------------------------
# REQUIRED VARIABLES
# -----------------------------------------------------------------------------

variable "project_id" {
  description = "The GCP project ID containing the VPC flow logs"
  type        = string
}

variable "sink_name" {
  description = "Name of the log sink"
  type        = string
}

variable "destination" {
  description = "The destination for the log sink. Format: bigquery.googleapis.com/projects/[PROJECT]/datasets/[DATASET], storage.googleapis.com/[BUCKET], or pubsub.googleapis.com/projects/[PROJECT]/topics/[TOPIC]"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# SINK CONFIGURATION
# -----------------------------------------------------------------------------

variable "description" {
  description = "Description of the log sink"
  type        = string
  default     = "VPC Flow Logs export sink"
}

variable "custom_filter" {
  description = "Custom filter for the log sink. If empty, defaults to VPC flow logs filter."
  type        = string
  default     = ""
}

variable "disabled" {
  description = "Whether the sink is disabled"
  type        = bool
  default     = false
}

variable "exclusions" {
  description = "Log exclusions for the sink"
  type = list(object({
    name        = string
    description = optional(string)
    filter      = string
    disabled    = optional(bool, false)
  }))
  default = []
}

variable "destination_type" {
  description = "Type of destination (bigquery, storage, pubsub). Auto-detected from destination if possible."
  type        = string
  default     = "bigquery"

  validation {
    condition     = contains(["bigquery", "storage", "pubsub"], var.destination_type)
    error_message = "destination_type must be one of: bigquery, storage, pubsub."
  }
}

variable "destination_project_id" {
  description = "Project ID where the destination resource exists (defaults to project_id)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# BIGQUERY CONFIGURATION
# -----------------------------------------------------------------------------

variable "create_bigquery_dataset" {
  description = "Whether to create a BigQuery dataset for flow logs"
  type        = bool
  default     = false
}

variable "bigquery_dataset_id" {
  description = "BigQuery dataset ID for flow logs"
  type        = string
  default     = "vpc_flow_logs"
}

variable "bigquery_location" {
  description = "Location for the BigQuery dataset"
  type        = string
  default     = "US"
}

variable "bigquery_use_partitioned_tables" {
  description = "Use partitioned tables for better query performance"
  type        = bool
  default     = true
}

variable "bigquery_delete_contents_on_destroy" {
  description = "Delete dataset contents when destroying"
  type        = bool
  default     = false
}

variable "bigquery_table_expiration_days" {
  description = "Default table expiration in days (null for no expiration)"
  type        = number
  default     = null
}

variable "bigquery_partition_expiration_days" {
  description = "Default partition expiration in days (null for no expiration)"
  type        = number
  default     = 90
}

# -----------------------------------------------------------------------------
# CLOUD STORAGE CONFIGURATION
# -----------------------------------------------------------------------------

variable "create_storage_bucket" {
  description = "Whether to create a Cloud Storage bucket for flow logs"
  type        = bool
  default     = false
}

variable "storage_bucket_name" {
  description = "Cloud Storage bucket name for flow logs"
  type        = string
  default     = ""
}

variable "storage_location" {
  description = "Location for the Cloud Storage bucket"
  type        = string
  default     = "US"
}

variable "storage_class" {
  description = "Storage class for the bucket"
  type        = string
  default     = "STANDARD"
}

variable "storage_force_destroy" {
  description = "Force destroy bucket contents when destroying"
  type        = bool
  default     = false
}

variable "storage_retention_days" {
  description = "Days before deleting log files (null for no deletion)"
  type        = number
  default     = 365
}

variable "storage_archive_days" {
  description = "Days before archiving log files (null for no archival)"
  type        = number
  default     = 90
}

# -----------------------------------------------------------------------------
# PUB/SUB CONFIGURATION
# -----------------------------------------------------------------------------

variable "pubsub_topic_name" {
  description = "Pub/Sub topic name for flow logs (when using pubsub destination)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# COMMON
# -----------------------------------------------------------------------------

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default     = {}
}
