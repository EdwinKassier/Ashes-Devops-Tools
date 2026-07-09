/**
 * Copyright 2023 Ashes
 *
 * Subnet Module - Variables
 */

variable "project_id" {
  description = "The ID of the project where the subnet will be created"
  type        = string
}

variable "subnet_name" {
  description = "Name of the subnet (lowercase letters, digits, hyphens; starts with letter; max 63 characters)"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.subnet_name))
    error_message = "subnet_name must start with a lowercase letter and contain only lowercase letters, digits, and hyphens (max 63 characters)."
  }
}

variable "ip_cidr_range" {
  description = "The range of internal addresses for this subnet (e.g. 10.0.0.0/24). Must be valid CIDR notation with no host bits set."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.ip_cidr_range))
    error_message = "ip_cidr_range must be valid CIDR notation (e.g. \"10.0.0.0/24\")."
  }

  validation {
    condition     = can(cidrnetmask(var.ip_cidr_range)) ? cidrhost(var.ip_cidr_range, 0) == split("/", var.ip_cidr_range)[0] : true
    error_message = "ip_cidr_range must not have host bits set (e.g. use \"10.0.0.0/24\", not \"10.0.1.128/24\")."
  }
}

variable "region" {
  description = "The GCP region where the subnet will be created (e.g. europe-west1)"
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a valid GCP region name (e.g. \"europe-west1\", \"us-central1\")."
  }
}

variable "network" {
  description = "The VPC network ID to attach this subnet to"
  type        = string
}

variable "private_ip_google_access" {
  description = "When enabled, VMs in this subnet can access Google APIs and services without external IPs"
  type        = bool
  default     = true
}

variable "enable_flow_logs" {
  description = "Whether to enable VPC flow logs for this subnet"
  type        = bool
  default     = true
}

variable "log_config_aggregation_interval" {
  description = "Aggregation interval for collecting flow logs"
  type        = string
  default     = "INTERVAL_5_SEC"

  validation {
    condition     = contains(["INTERVAL_5_SEC", "INTERVAL_30_SEC", "INTERVAL_1_MIN", "INTERVAL_5_MIN", "INTERVAL_10_MIN", "INTERVAL_15_MIN"], var.log_config_aggregation_interval)
    error_message = "log_config_aggregation_interval must be one of: INTERVAL_5_SEC, INTERVAL_30_SEC, INTERVAL_1_MIN, INTERVAL_5_MIN, INTERVAL_10_MIN, INTERVAL_15_MIN."
  }
}

variable "log_config_flow_sampling" {
  description = "Sampling rate for VPC flow logs (0.0 to 1.0)"
  type        = number
  default     = 0.5
}

variable "log_config_metadata" {
  description = "Metadata to include in flow logs"
  type        = string
  default     = "INCLUDE_ALL_METADATA"

  validation {
    condition     = contains(["INCLUDE_ALL_METADATA", "EXCLUDE_ALL_METADATA", "CUSTOM_METADATA"], var.log_config_metadata)
    error_message = "log_config_metadata must be one of: INCLUDE_ALL_METADATA, EXCLUDE_ALL_METADATA, CUSTOM_METADATA."
  }
}

variable "secondary_ip_ranges" {
  description = "Secondary IP ranges for the subnet (useful for GKE pods/services)"
  type = list(object({
    range_name    = string
    ip_cidr_range = string
  }))
  default = []
}

variable "purpose" {
  description = "Purpose of the subnet (PRIVATE, REGIONAL_MANAGED_PROXY, GLOBAL_MANAGED_PROXY, PRIVATE_SERVICE_CONNECT, PEER_MIGRATION)"
  type        = string
  default     = null

  validation {
    condition     = var.purpose == null ? true : contains(["PRIVATE", "REGIONAL_MANAGED_PROXY", "GLOBAL_MANAGED_PROXY", "PRIVATE_SERVICE_CONNECT", "PEER_MIGRATION"], var.purpose)
    error_message = "purpose must be one of: PRIVATE, REGIONAL_MANAGED_PROXY, GLOBAL_MANAGED_PROXY, PRIVATE_SERVICE_CONNECT, PEER_MIGRATION."
  }
}

variable "role" {
  description = "Role for the subnet when purpose is REGIONAL_MANAGED_PROXY or GLOBAL_MANAGED_PROXY (ACTIVE or BACKUP)"
  type        = string
  default     = null

  validation {
    condition     = var.role == null ? true : contains(["ACTIVE", "BACKUP"], var.role)
    error_message = "role must be either ACTIVE or BACKUP."
  }
}
