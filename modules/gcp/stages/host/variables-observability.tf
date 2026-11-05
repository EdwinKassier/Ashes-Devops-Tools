# Host stage (observability) inputs. Part of modules/gcp/stages/host.

# =============================================================================
# VPC FLOW LOGS EXPORT CONFIGURATION
# =============================================================================

variable "enable_vpc_flow_logs_export" {
  description = "Enable VPC Flow Logs export to BigQuery or Cloud Storage"
  type        = bool
  default     = false
}

variable "vpc_flow_logs_sink_name" {
  description = "Name of the VPC Flow Logs sink"
  type        = string
  default     = "vpc-flow-logs-sink"
}

variable "vpc_flow_logs_destination" {
  description = "Logging sink destination URI for VPC Flow Logs export (e.g., bigquery.googleapis.com/projects/PROJECT/datasets/DATASET). Required when enable_vpc_flow_logs_export is true and vpc_flow_logs_create_bigquery_dataset is false."
  type        = string
  default     = ""

  validation {
    condition = (
      !var.enable_vpc_flow_logs_export ||
      var.vpc_flow_logs_create_bigquery_dataset ||
      var.vpc_flow_logs_destination != ""
    )
    error_message = "vpc_flow_logs_destination must be set when enable_vpc_flow_logs_export is true and vpc_flow_logs_create_bigquery_dataset is false."
  }
}

variable "vpc_flow_logs_create_bigquery_dataset" {
  description = "Whether to create a BigQuery dataset for flow logs"
  type        = bool
  default     = false
}

variable "vpc_flow_logs_bigquery_dataset_id" {
  description = "BigQuery dataset ID for flow logs"
  type        = string
  default     = "vpc_flow_logs"
}

variable "vpc_flow_logs_bigquery_location" {
  description = "Location for the BigQuery dataset"
  type        = string
  default     = "US"
}

variable "vpc_flow_logs_create_storage_bucket" {
  description = "Whether to create a Cloud Storage bucket for flow logs"
  type        = bool
  default     = false
}

variable "vpc_flow_logs_storage_bucket_name" {
  description = "Cloud Storage bucket name for flow logs"
  type        = string
  default     = ""
}

variable "vpc_flow_logs_storage_location" {
  description = "Location for the Cloud Storage bucket"
  type        = string
  default     = "US"
}

variable "vpc_flow_logs_retention_days" {
  description = "Days to retain flow logs data"
  type        = number
  default     = 90
}

# =============================================================================
# PACKET MIRRORING CONFIGURATION
# =============================================================================

variable "packet_mirroring_policies" {
  description = "Map of packet mirroring policies to create"
  type = map(object({
    region               = string
    collector_ilb_url    = string
    mirrored_instances   = optional(list(string), [])
    mirrored_subnetworks = optional(list(string), [])
    mirrored_tags        = optional(list(string), [])
    filter_ip_protocols  = optional(list(string), [])
    filter_cidr_ranges   = optional(list(string), [])
    filter_direction     = optional(string, "BOTH")
    priority             = optional(number, 1000)
    enable               = optional(bool, true)
  }))
  default = {}
}

