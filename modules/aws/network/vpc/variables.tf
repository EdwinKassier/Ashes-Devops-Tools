variable "name" {
  description = "Name applied to the VPC and used as the prefix for subnet Name tags."
  type        = string
  default     = "landing-zone"

  validation {
    condition     = length(trimspace(var.name)) > 0
    error_message = "name must be a non-empty string."
  }
}

variable "cidr_block" {
  description = "IPv4 CIDR used for subnet math (cidrsubnet). Also the VPC CIDR: literal when ipam_pool_id is empty, otherwise the exact block requested from the IPAM pool."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    # cidrnetmask fails on a malformed CIDR, so a successful call proves the
    # value parses as a valid IPv4 CIDR block.
    condition     = can(cidrnetmask(var.cidr_block))
    error_message = "cidr_block must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}

variable "ipam_pool_id" {
  description = "IPAM pool ID the VPC allocates from. When set, the VPC allocates from the pool (see ipam_allocation); empty string uses cidr_block as a static CIDR. Adding a pool to an existing static VPC forces replacement."
  type        = string
  default     = ""
}

variable "ipam_allocation" {
  description = "How an IPAM VPC obtains its CIDR: explicit_cidr (default: pool + cidr_block, so the pool allocates exactly the block the subnets are cut from) or netmask (legacy: pool + netmask_length). An existing netmask VPC keeps its id when you switch, because ipv4_netmask_length is ignored after create. If the allocated block differs from cidr_block, set cidr_block to the allocated block so the subnet math matches. Ignored when ipam_pool_id is empty."
  type        = string
  default     = "explicit_cidr"
  nullable    = false

  validation {
    condition     = contains(["netmask", "explicit_cidr"], var.ipam_allocation)
    error_message = "ipam_allocation must be netmask or explicit_cidr."
  }
}

variable "netmask_length" {
  description = "Netmask length requested from the IPAM pool when ipam_pool_id is set and ipam_allocation = netmask. Ignored for static and explicit_cidr VPCs. Used only at create: a later change is ignored and does not replace the VPC."
  type        = number
  default     = 16

  validation {
    condition     = var.netmask_length >= 16 && var.netmask_length <= 28
    error_message = "netmask_length must be between 16 and 28."
  }
}

variable "enable_ipv6" {
  description = "Whether to assign an Amazon-provided /56 IPv6 CIDR block to the VPC."
  type        = bool
  default     = false
}

variable "region" {
  description = "AWS region, used to build gateway endpoint service names (com.amazonaws.<region>.<service>)."
  type        = string

  validation {
    condition     = length(trimspace(var.region)) > 0
    error_message = "region must be a non-empty string."
  }
}

variable "availability_zones" {
  description = "Availability zones to place subnets in. Only the first az_count entries are used."
  type        = list(string)
  default     = ["eu-west-2a", "eu-west-2b", "eu-west-2c"]

  validation {
    condition     = length(var.availability_zones) > 0
    error_message = "availability_zones must contain at least one zone."
  }
}

variable "az_count" {
  description = "Number of availability zones to spread each subnet tier across. Must not exceed the number of availability_zones."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 1 && var.az_count <= 3
    error_message = "az_count must be between 1 and 3."
  }

  validation {
    condition     = var.az_count <= length(var.availability_zones)
    error_message = "az_count must not exceed the number of availability_zones provided."
  }
}

variable "subnets" {
  description = "Subnet tiers, keyed by tier name. newbits/number_offset drive cidrsubnet(cidr_block, newbits, number_offset + az_index); public toggles map_public_ip_on_launch."
  type = map(object({
    newbits       = number
    number_offset = number
    public        = optional(bool, false)
  }))
  default = {
    public   = { newbits = 8, number_offset = 0, public = true }
    private  = { newbits = 8, number_offset = 8 }
    isolated = { newbits = 8, number_offset = 16 }
  }

  validation {
    condition     = length(var.subnets) > 0
    error_message = "subnets must define at least one tier."
  }

  validation {
    condition     = alltrue([for cfg in values(var.subnets) : cfg.newbits > 0])
    error_message = "Every subnet tier newbits must be greater than 0."
  }
}

variable "flow_log_destination_arn" {
  description = "ARN of the S3 bucket (in the central log archive) that receives VPC flow logs."
  type        = string

  validation {
    condition     = can(regex("^arn:aws(-us-gov|-cn|-eusc)?:s3:::", var.flow_log_destination_arn))
    error_message = "flow_log_destination_arn must be an S3 bucket ARN beginning with arn:aws:s3:::."
  }
}

variable "gateway_endpoints" {
  description = "AWS services to create Gateway VPC endpoints for (e.g. s3, dynamodb)."
  type        = list(string)
  default     = ["s3", "dynamodb"]
}

variable "gateway_endpoint_policies" {
  description = "Endpoint policy (JSON string) per gateway endpoint service, keyed like gateway_endpoints (e.g. s3, dynamodb). A service without an entry gets no policy argument, so AWS applies its default full-access policy. Build the JSON with jsonencode."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for k in keys(var.gateway_endpoint_policies) : contains(var.gateway_endpoints, k)])
    error_message = "Every gateway_endpoint_policies key must be a service listed in gateway_endpoints."
  }

  validation {
    condition     = alltrue([for k, v in var.gateway_endpoint_policies : can(jsondecode(v).Statement)])
    error_message = "Every gateway_endpoint_policies value must be a JSON policy document with a Statement."
  }
}

variable "gateway_endpoint_tiers" {
  description = "Subnet tiers whose route tables the gateway endpoints are associated with. null (default) associates them with every non-public tier."
  type        = list(string)
  default     = null

  validation {
    condition     = var.gateway_endpoint_tiers == null || alltrue([for t in coalesce(var.gateway_endpoint_tiers, []) : contains(keys(var.subnets), t)])
    error_message = "Every gateway_endpoint_tiers entry must be a tier defined in subnets."
  }
}

variable "create_internet_gateway" {
  description = "Whether this module creates an internet gateway. When true, every public tier (public = true) route table gets a 0.0.0.0/0 default route to it."
  type        = bool
  default     = false
}

variable "routes" {
  description = "Static routes keyed by subnet tier; each route is added to EVERY AZ route table of that tier. Set exactly one target per route (e.g. transit_gateway_id for spoke default routing to the hub). Per-AZ targets (such as per-AZ NAT gateways) should instead be added by the caller against route_table_ids_by_tier."
  type = map(list(object({
    destination_cidr_block    = string
    transit_gateway_id        = optional(string)
    nat_gateway_id            = optional(string)
    gateway_id                = optional(string)
    vpc_endpoint_id           = optional(string)
    network_interface_id      = optional(string)
    vpc_peering_connection_id = optional(string)
  })))
  default = {}

  validation {
    condition     = alltrue([for tier in keys(var.routes) : contains(keys(var.subnets), tier)])
    error_message = "Every routes key must be a tier defined in subnets."
  }

  validation {
    condition     = alltrue(flatten([for rs in values(var.routes) : [for r in rs : can(cidrnetmask(r.destination_cidr_block))]]))
    error_message = "Every route destination_cidr_block must be a valid IPv4 CIDR block."
  }

  validation {
    # Exactly one target per route. Uses null-ness (not values) so targets that
    # are unknown until apply (e.g. a TGW id from another resource) still pass.
    condition = alltrue(flatten([for rs in values(var.routes) : [for r in rs : length([
      for t in [r.transit_gateway_id, r.nat_gateway_id, r.gateway_id, r.vpc_endpoint_id, r.network_interface_id, r.vpc_peering_connection_id] : t if t != null
    ]) == 1]]))
    error_message = "Every route must set exactly one target (transit_gateway_id, nat_gateway_id, gateway_id, vpc_endpoint_id, network_interface_id or vpc_peering_connection_id)."
  }

  validation {
    condition     = alltrue([for rs in values(var.routes) : length(rs) == length(distinct([for r in rs : r.destination_cidr_block]))])
    error_message = "Destination CIDRs must be unique within a tier."
  }
}

variable "tags" {
  description = "Tags applied to every taggable resource this module creates (merged under the per-resource Name/Tier tags). Org-wide tags (CostCenter, Environment, Owner, ...) normally come from the provider default_tags; use this for module-specific additions."
  type        = map(string)
  default     = {}
}
