variable "org_id" {
  description = "AWS Organizations org id (o-xxxxxxxxxx) used to scope centralized VPC-endpoint access to this organization."
  type        = string

  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.org_id))
    error_message = "org_id must be an AWS Organizations org id (o-xxxxxxxxxx)."
  }
}

variable "org_arn" {
  description = "ARN of the AWS Organization (arn:aws:organizations::<mgmt-account>:organization/o-xxxx) used as the RAM principal so the IPAM pools, transit gateway, and Route 53 Profile are shared org-wide."
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-us-gov|-cn)?:organizations::", var.org_arn))
    error_message = "org_arn must be an AWS Organizations ARN beginning with arn:aws:organizations::."
  }
}

variable "aws_region" {
  description = "AWS region the network hub is deployed in. Used for the inspection/egress VPCs, gateway/interface endpoint service names, and NAT placement."
  type        = string
  default     = "eu-west-2"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[1-9][0-9]?$", var.aws_region))
    error_message = "aws_region must be a valid AWS region id (e.g. eu-west-2)."
  }
}

variable "aws_enabled_regions" {
  description = "Regions IPAM operates in. Each becomes an operating region on the IPAM and gets its own regional pool."
  type        = list(string)
  default     = ["eu-west-2"]

  validation {
    condition     = length(var.aws_enabled_regions) > 0
    error_message = "aws_enabled_regions must contain at least one region."
  }
}

variable "top_cidr" {
  description = "CIDR of the top-level supernet owned by the top IPAM pool."
  type        = string
  default     = "10.0.0.0/8"

  validation {
    condition     = can(cidrhost(var.top_cidr, 0))
    error_message = "top_cidr must be a valid IPv4 CIDR block (e.g. 10.0.0.0/8)."
  }
}

variable "regional_cidrs" {
  description = "Map of region to the CIDR each regional IPAM pool provisions. Every CIDR should fall within top_cidr."
  type        = map(string)
  default     = { eu-west-2 = "10.0.0.0/12" }

  validation {
    condition     = alltrue([for c in values(var.regional_cidrs) : can(cidrhost(c, 0))])
    error_message = "Every value in regional_cidrs must be a valid IPv4 CIDR block."
  }
}

variable "inspection_cidr" {
  description = "IPv4 CIDR of the inspection VPC that hosts the Network Firewall endpoints and its transit-gateway attachment."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.inspection_cidr))
    error_message = "inspection_cidr must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}

variable "egress_cidr" {
  description = "IPv4 CIDR of the centralized egress VPC that hosts the NAT gateways, interface endpoints, and Route 53 resolver endpoints."
  type        = string
  default     = "10.1.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.egress_cidr))
    error_message = "egress_cidr must be a valid IPv4 CIDR block (e.g. 10.1.0.0/16)."
  }
}

variable "availability_zones" {
  description = "Availability zones to spread each subnet tier across. Only the first az_count entries are used."
  type        = list(string)
  default     = ["eu-west-2a", "eu-west-2b"]

  validation {
    condition     = length(var.availability_zones) > 0
    error_message = "availability_zones must contain at least one zone."
  }
}

variable "az_count" {
  description = "Number of availability zones to spread each subnet tier across."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be between 2 and 3 (the Route 53 Resolver endpoints need subnets in at least two AZs)."
  }

  validation {
    condition     = var.az_count <= length(var.availability_zones)
    error_message = "az_count must not exceed the number of availability_zones provided."
  }
}

variable "flow_log_destination_arn" {
  description = "ARN of the S3 bucket (in the central log archive) that receives VPC flow logs and Route 53 resolver query logs."
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-us-gov|-cn)?:s3:::", var.flow_log_destination_arn))
    error_message = "flow_log_destination_arn must be an S3 bucket ARN beginning with arn:aws:s3:::."
  }
}

variable "log_bucket_name" {
  description = "Name of the S3 bucket that receives Network Firewall flow logs."
  type        = string

  validation {
    condition     = length(trimspace(var.log_bucket_name)) > 0
    error_message = "log_bucket_name must be a non-empty string."
  }
}

variable "private_hosted_zone_name" {
  description = "Name of the shared Route 53 private hosted zone for split-horizon DNS in the egress VPC. Empty string skips creating the zone."
  type        = string
  default     = ""
}

variable "enable_network_firewall" {
  description = "Whether to deploy the Network Firewall in the inspection VPC. COST TOGGLE: bills per endpoint-hour plus per-GB processed."
  type        = bool
  default     = true
}

variable "network_firewall_managed_rule_groups" {
  description = "AWS-managed StrictOrder stateful rule group names attached to the inspection firewall policy (see modules/aws/network/network-firewall managed_rule_groups)."
  type        = list(string)
  default = [
    "AttackInfrastructureStrictOrder",
    "MalwareDomainsStrictOrder",
    "BotNetCommandAndControlDomainsStrictOrder",
  ]
}

variable "network_firewall_stateful_default_actions" {
  description = "STRICT_ORDER default actions for unmatched traffic. Default [\"aws:alert_established\"] = log-but-pass (no day-one blackhole); move to [\"aws:drop_established\", \"aws:alert_established\"] once allow rules cover legitimate egress."
  type        = list(string)
  default     = ["aws:alert_established"]
}

variable "network_firewall_egress_domain_allowlist" {
  description = "Optional HTTP_HOST/TLS_SNI egress domain allowlist. Non-empty DROPS all other HTTP/TLS egress from the org supernet (top_cidr). Empty (default) = no domain filtering."
  type        = list(string)
  default     = []
}

variable "enforce_egress_allowlist" {
  description = "Production egress gate. When true (and egress_alert_only_waived is false) the plan fails unless network_firewall_stateful_default_actions contains aws:drop_established and network_firewall_egress_domain_allowlist is non-empty, so production never runs alert-only. The aws-network root sets it when org.profile is production and an AWS workload environment is_production."
  type        = bool
  default     = false
}

variable "egress_alert_only_waived" {
  description = "Explicit, reviewable waiver of the production egress gate: accept alert-only (log-but-pass) egress inspection while allow rules are being built. Only meaningful when enforce_egress_allowlist is true."
  type        = bool
  default     = false
}

variable "network_firewall_suricata_rules" {
  description = "Optional custom Suricata rules (STRICT_ORDER semantics) evaluated after the managed threat groups. Empty (default) = none."
  type        = string
  default     = ""
}

variable "enable_network_access_analyzer" {
  description = "Whether to create the Network Access Analyzer scope that flags segmentation-intent violations. Off by default."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to the stage's own taggable resources (NAT gateways, EIPs) and passed to every child module (hub VPCs, IPAM, TGW, Network Firewall, endpoints, Resolver, Network Access Analyzer). Org-wide tags normally come from the provider default_tags; use this for stage-specific additions."
  type        = map(string)
  default     = {}
}

variable "ipam_mode_for_new_vpcs_only" {
  description = "When true (default), the hub VPCs allocate from the regional IPAM pool only if named in ipam_new_vpcs; all others keep their static CIDR attributes (adding a pool to an existing VPC forces replacement). Set false to move BOTH hub VPCs to the pool (replaces them; the destroy guard blocks it unless overridden)."
  type        = bool
  default     = true
  nullable    = false
}

variable "ipam_new_vpcs" {
  description = "Hub VPCs to create from the regional IPAM pool while ipam_mode_for_new_vpcs_only is true. Allowed: inspection, egress. List a VPC only when it is being created; listing an existing static VPC replaces it."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for v in var.ipam_new_vpcs : contains(["inspection", "egress"], v)])
    error_message = "ipam_new_vpcs may only contain inspection and egress."
  }
}

variable "enable_vpn" {
  description = "Attach an on-premises Site-to-Site VPN to the transit gateway (network/vpn). Off by default. Requires vpn.customer_gateway_ip. Traffic from on-premises is default-routed to the inspection VPC (a dedicated hybrid TGW route table), and the on-premises routes propagate only into the inspection route table, so spoke return traffic is inspected too. See docs/architecture/aws-landing-zone.md."
  type        = bool
  default     = false
  nullable    = false
}

variable "vpn" {
  description = <<-EOT
    Site-to-Site VPN settings, used only when enable_vpn is true. customer_gateway_ip is the public IPv4 of the on-premises device; customer_gateway_bgp_asn its BGP ASN (not the transit gateway's 64512). static_routes_only = true uses static routing: then onprem_cidrs (the on-premises prefixes) is required and becomes static routes to the VPN in the inspection route table; with BGP the routes propagate and onprem_cidrs is ignored. tunnel_inside_cidrs is empty (AWS-assigned) or two /30s in 169.254.0.0/16. preshared_key_storage is SecretsManager (default; the keys stay out of state and the stage outputs the secret ARN) or Standard (keys in state).
  EOT
  type = object({
    customer_gateway_ip      = optional(string)
    customer_gateway_bgp_asn = optional(number, 65000)
    static_routes_only       = optional(bool, false)
    onprem_cidrs             = optional(list(string), [])
    tunnel_inside_cidrs      = optional(list(string), [])
    enable_acceleration      = optional(bool, false)
    preshared_key_storage    = optional(string, "SecretsManager")
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.enable_vpn || (var.vpn.customer_gateway_ip != null && can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.vpn.customer_gateway_ip)))
    error_message = "vpn.customer_gateway_ip must be the on-premises device's public IPv4 address when enable_vpn is true."
  }

  validation {
    condition     = var.vpn.customer_gateway_bgp_asn >= 1 && var.vpn.customer_gateway_bgp_asn <= 4294967294 && var.vpn.customer_gateway_bgp_asn != 64512
    error_message = "vpn.customer_gateway_bgp_asn must be 1 to 4294967294 and differ from the transit gateway's Amazon-side ASN (64512)."
  }

  validation {
    condition     = !var.vpn.static_routes_only || length(var.vpn.onprem_cidrs) > 0
    error_message = "vpn.static_routes_only = true needs vpn.onprem_cidrs (the on-premises prefixes to route to the VPN)."
  }

  validation {
    condition     = alltrue([for c in var.vpn.onprem_cidrs : can(cidrnetmask(c))])
    error_message = "vpn.onprem_cidrs entries must be IPv4 CIDR blocks."
  }

  validation {
    condition     = contains(["SecretsManager", "Standard"], var.vpn.preshared_key_storage)
    error_message = "vpn.preshared_key_storage must be SecretsManager or Standard."
  }
}
