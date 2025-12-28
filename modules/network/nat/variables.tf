/**
 * Copyright 2023 Ashes
 *
 * Cloud NAT Module - Variables
 */

# -----------------------------------------------------------------------------
# REQUIRED VARIABLES
# -----------------------------------------------------------------------------

variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "name" {
  description = "Name of the Cloud NAT gateway"
  type        = string
}

variable "region" {
  description = "The region where the NAT gateway will be created"
  type        = string
}

variable "network" {
  description = "The network (self_link or name) to create the router in"
  type        = string
}

# -----------------------------------------------------------------------------
# ROUTER CONFIGURATION
# -----------------------------------------------------------------------------

variable "create_router" {
  description = "Whether to create a new Cloud Router. Set to false if using an existing router."
  type        = bool
  default     = true
}

variable "router_name" {
  description = "Name of the Cloud Router. Required if create_router is false, otherwise auto-generated."
  type        = string
  default     = ""
}

variable "router_asn" {
  description = "BGP ASN for the Cloud Router (optional)"
  type        = number
  default     = null
}

# -----------------------------------------------------------------------------
# NAT IP ALLOCATION
# -----------------------------------------------------------------------------

variable "nat_ip_allocate_option" {
  description = "How external IPs should be allocated. AUTO_ONLY or MANUAL_ONLY."
  type        = string
  default     = "AUTO_ONLY"

  validation {
    condition     = contains(["AUTO_ONLY", "MANUAL_ONLY"], var.nat_ip_allocate_option)
    error_message = "nat_ip_allocate_option must be either 'AUTO_ONLY' or 'MANUAL_ONLY'."
  }
}

variable "nat_ips" {
  description = "List of external IP addresses to use for NAT (when using MANUAL_ONLY)"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# SUBNETWORK CONFIGURATION
# -----------------------------------------------------------------------------

variable "source_subnetwork_ip_ranges_to_nat" {
  description = "How NAT should be applied to subnetworks. ALL_SUBNETWORKS_ALL_IP_RANGES, ALL_SUBNETWORKS_ALL_PRIMARY_IP_RANGES, or LIST_OF_SUBNETWORKS."
  type        = string
  default     = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  validation {
    condition     = contains(["ALL_SUBNETWORKS_ALL_IP_RANGES", "ALL_SUBNETWORKS_ALL_PRIMARY_IP_RANGES", "LIST_OF_SUBNETWORKS"], var.source_subnetwork_ip_ranges_to_nat)
    error_message = "source_subnetwork_ip_ranges_to_nat must be one of: ALL_SUBNETWORKS_ALL_IP_RANGES, ALL_SUBNETWORKS_ALL_PRIMARY_IP_RANGES, LIST_OF_SUBNETWORKS."
  }
}

variable "subnetworks" {
  description = "List of subnetworks to NAT (when using LIST_OF_SUBNETWORKS)"
  type = list(object({
    name                     = string
    source_ip_ranges_to_nat  = list(string)
    secondary_ip_range_names = optional(list(string))
  }))
  default = []
}

# -----------------------------------------------------------------------------
# PORT ALLOCATION
# -----------------------------------------------------------------------------

variable "min_ports_per_vm" {
  description = "Minimum number of ports allocated to a VM"
  type        = number
  default     = 64
}

variable "max_ports_per_vm" {
  description = "Maximum number of ports allocated to a VM (requires enable_dynamic_port_allocation)"
  type        = number
  default     = null
}

variable "enable_dynamic_port_allocation" {
  description = "Enable Dynamic Port Allocation for better port utilization"
  type        = bool
  default     = false
}

variable "enable_endpoint_independent_mapping" {
  description = "Enable endpoint-independent mapping for consistent NAT behavior"
  type        = bool
  default     = null
}

# -----------------------------------------------------------------------------
# TIMEOUTS
# -----------------------------------------------------------------------------

variable "udp_idle_timeout_sec" {
  description = "Timeout for UDP connections (seconds)"
  type        = number
  default     = 30
}

variable "icmp_idle_timeout_sec" {
  description = "Timeout for ICMP connections (seconds)"
  type        = number
  default     = 30
}

variable "tcp_established_idle_timeout_sec" {
  description = "Timeout for established TCP connections (seconds)"
  type        = number
  default     = 1200
}

variable "tcp_transitory_idle_timeout_sec" {
  description = "Timeout for transitory TCP connections (seconds)"
  type        = number
  default     = 30
}

variable "tcp_time_wait_timeout_sec" {
  description = "Timeout for TCP connections in TIME_WAIT state (seconds)"
  type        = number
  default     = 120
}

# -----------------------------------------------------------------------------
# LOGGING
# -----------------------------------------------------------------------------

variable "enable_logging" {
  description = "Enable NAT logging"
  type        = bool
  default     = true
}

variable "log_filter" {
  description = "NAT log filter: ERRORS_ONLY, TRANSLATIONS_ONLY, or ALL"
  type        = string
  default     = "ERRORS_ONLY"

  validation {
    condition     = contains(["ERRORS_ONLY", "TRANSLATIONS_ONLY", "ALL"], var.log_filter)
    error_message = "log_filter must be one of: ERRORS_ONLY, TRANSLATIONS_ONLY, ALL."
  }
}
