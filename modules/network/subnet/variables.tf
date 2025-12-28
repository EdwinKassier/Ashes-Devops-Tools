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
  description = "Name of the subnet"
  type        = string
}

variable "ip_cidr_range" {
  description = "The range of internal addresses for this subnet"
  type        = string
}

variable "region" {
  description = "The region where the subnet will be created"
  type        = string
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
  description = "Purpose of the subnet (PRIVATE, REGIONAL_MANAGED_PROXY, etc.)"
  type        = string
  default     = null
}

variable "role" {
  description = "Role for the subnet when purpose is set (ACTIVE or BACKUP)"
  type        = string
  default     = null
}
