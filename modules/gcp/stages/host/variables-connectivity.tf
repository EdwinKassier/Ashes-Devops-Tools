# Host stage (connectivity) inputs. Part of modules/gcp/stages/host.

# =============================================================================
# VPN CONFIGURATION
# =============================================================================

variable "enable_vpn" {
  description = "Enable Cloud VPN for hybrid connectivity"
  type        = bool
  default     = false
}

variable "vpn_tunnel_count" {
  description = "Number of VPN tunnels per gateway. Use 2 for HA VPN (recommended for production); 1 for testing only."
  type        = number
  default     = 2
  validation {
    condition     = contains([1, 2], var.vpn_tunnel_count)
    error_message = "vpn_tunnel_count must be 1 or 2."
  }
}

variable "vpn_router_asn" {
  description = "Cloud Router BGP ASN"
  type        = number
  default     = 64512
}

variable "vpn_peer_asn" {
  description = "Peer router BGP ASN"
  type        = number
  default     = 64513
}

variable "vpn_peer_gateway_ips" {
  description = <<-EOT
    List of external IPv4 addresses for the peer VPN gateway interfaces.
    Provide one IP for single-tunnel VPNs or two distinct IPs for HA (tunnel_count = 2).
    Example single: ["203.0.113.1"]
    Example HA:     ["203.0.113.1", "203.0.113.2"]
  EOT
  type        = list(string)
  default     = []
}

variable "vpn_shared_secret" {
  description = "VPN shared secret. Must be set when enable_vpn = true. Consider injecting via Secret Manager rather than a plaintext tfvars value."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = !var.enable_vpn || (var.vpn_shared_secret != null && var.vpn_shared_secret != "")
    error_message = "vpn_shared_secret must be set (non-null, non-empty) when enable_vpn is true."
  }
}

variable "vpn_local_ips" {
  description = "Local IP addresses for VPN interfaces"
  type        = list(string)
  default     = ["169.254.0.1", "169.254.0.3"]
}

variable "vpn_peer_ips" {
  description = "Peer IP addresses for BGP sessions"
  type        = list(string)
  default     = ["169.254.0.2", "169.254.0.4"]
}

variable "vpn_advertised_ip_ranges" {
  description = "IP ranges to advertise via BGP"
  type = list(object({
    range       = string
    description = string
  }))
  default = []
}

# =============================================================================
# VPC PEERING CONFIGURATION
# =============================================================================

variable "vpc_peerings" {
  description = "Map of VPC peering configurations"
  type = map(object({
    peer_network           = string
    create_reverse_peering = optional(bool, true)
    export_custom_routes   = optional(bool, false)
    import_custom_routes   = optional(bool, false)
  }))
  default = {}
}

# =============================================================================
# STANDALONE NAT GATEWAY CONFIGURATION
# =============================================================================

variable "standalone_nat_gateways" {
  description = "Map of standalone NAT gateways to create (for multi-region or custom NAT configurations)"
  type = map(object({
    region                             = string
    create_router                      = optional(bool, true)
    router_name                        = optional(string)
    nat_ip_allocate_option             = optional(string, "AUTO_ONLY")
    nat_ips                            = optional(list(string), [])
    source_subnetwork_ip_ranges_to_nat = optional(string, "ALL_SUBNETWORKS_ALL_IP_RANGES")
    subnetworks = optional(list(object({
      name                     = string
      source_ip_ranges_to_nat  = list(string)
      secondary_ip_range_names = optional(list(string))
    })), [])
    min_ports_per_vm               = optional(number, 64)
    enable_dynamic_port_allocation = optional(bool, false)
    enable_logging                 = optional(bool, true)
    log_filter                     = optional(string, "ERRORS_ONLY")
  }))
  default = {}
}

# =============================================================================
# INTERCONNECT CONFIGURATION
# =============================================================================

variable "interconnects" {
  description = "Map of Cloud Interconnect attachments to create"
  type = map(object({
    region            = string
    interconnect_type = optional(string, "PARTNER")
    router_name       = string
    router_asn        = optional(number, 64512)
    create_router     = optional(bool, true)

    # Dedicated interconnect settings
    interconnect_self_link = optional(string)
    vlan_tag               = optional(number)
    bandwidth              = optional(string, "BPS_10G")

    # Partner interconnect settings
    edge_availability_domain = optional(string, "AVAILABILITY_DOMAIN_1")

    # Common settings
    mtu           = optional(number, 1440)
    admin_enabled = optional(bool, true)
    encryption    = optional(string, "NONE")

    # BGP settings
    create_bgp_peer    = optional(bool, true)
    interface_ip_range = optional(string)
    peer_ip_address    = optional(string)
    peer_asn           = optional(number, 65000)
    enable_bfd         = optional(bool, false)

    advertised_ip_ranges = optional(list(object({
      range       = string
      description = optional(string)
    })), [])
  }))
  default = {}
}

