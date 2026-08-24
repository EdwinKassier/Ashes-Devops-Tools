variable "name" {
  description = "Name prefix for the VPN resources (customer gateway, connection)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,48}$", var.name))
    error_message = "name must be 1-48 chars of letters, digits, or hyphens."
  }
}

variable "customer_gateway_ip" {
  description = "Public IP address of the on-premises (customer) VPN device."
  type        = string

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.customer_gateway_ip))
    error_message = "customer_gateway_ip must be a valid IPv4 address."
  }
}

variable "customer_gateway_bgp_asn" {
  description = "BGP ASN of the customer gateway (used for dynamic routing)."
  type        = number
  default     = 65000
}

variable "attach_to" {
  description = "Where to terminate the VPN on the AWS side: 'transit_gateway' (set transit_gateway_id) or 'vpn_gateway' (set vpn_gateway_id)."
  type        = string
  default     = "transit_gateway"

  validation {
    condition     = contains(["transit_gateway", "vpn_gateway"], var.attach_to)
    error_message = "attach_to must be 'transit_gateway' or 'vpn_gateway'."
  }
}

variable "transit_gateway_id" {
  description = "Transit Gateway ID to attach the VPN connection to (required when attach_to = transit_gateway)."
  type        = string
  default     = null
}

variable "vpn_gateway_id" {
  description = "Virtual Private Gateway (VGW) ID to attach the VPN connection to (required when attach_to = vpn_gateway)."
  type        = string
  default     = null
}

variable "static_routes_only" {
  description = "Use static routing (true) instead of BGP dynamic routing (false). Dynamic (BGP) is preferred where the customer device supports it."
  type        = bool
  default     = false
}

variable "static_routes" {
  description = "Destination CIDR blocks for static routes (only used when static_routes_only = true)."
  type        = list(string)
  default     = []
}

variable "tunnel_inside_cidrs" {
  description = "Optional list of /30 inside CIDRs for the two tunnels (link-local 169.254.0.0/16). Empty = AWS-assigned."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.tunnel_inside_cidrs) == 0 || length(var.tunnel_inside_cidrs) == 2
    error_message = "tunnel_inside_cidrs must be empty or contain exactly two /30 CIDRs (one per tunnel)."
  }
}

variable "enable_acceleration" {
  description = "Enable AWS Global Accelerator for the VPN connection (requires a Transit Gateway attachment)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to the VPN resources."
  type        = map(string)
  default     = {}
}
