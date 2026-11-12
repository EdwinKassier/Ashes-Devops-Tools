variable "name_prefix" {
  description = "Prefix applied to the names of all resolver, profile, RAM, and DNS firewall resources."
  type        = string
  default     = "org"

  validation {
    condition     = length(trimspace(var.name_prefix)) > 0
    error_message = "name_prefix must be a non-empty string."
  }
}

variable "vpc_id" {
  description = "ID of the VPC that hosts the resolver endpoints and that the resolver rules, DNS firewall, query logging and DNSSEC are associated with. Other VPCs get the same rules, firewall and zones by associating the shared Route 53 Profile."
  type        = string

  validation {
    condition     = length(trimspace(var.vpc_id)) > 0
    error_message = "vpc_id must be a non-empty string."
  }
}

variable "enable_resolver_endpoints" {
  description = "Create the inbound and outbound Resolver endpoints (2 ENIs each, about USD 365 per month together). Needed for on-premises resolution in either direction and for forward_rules. Default false."
  type        = bool
  default     = false
  nullable    = false
}

variable "subnet_ids" {
  description = "Subnet IDs (one per AZ, at least two) for the endpoint IPs. Required when enable_resolver_endpoints is true."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = !var.enable_resolver_endpoints || length(var.subnet_ids) >= 2
    error_message = "subnet_ids must contain at least two subnets when enable_resolver_endpoints is true (resolver endpoints require a minimum of two IP addresses)."
  }
}

variable "security_group_ids" {
  description = "Security groups for the resolver endpoints. Empty (default) = a module-owned group that admits DNS (TCP and UDP 53) from allowed_cidrs. The provider replaces an endpoint when its security groups change."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "allowed_cidrs" {
  description = "CIDRs that may send DNS (TCP and UDP 53) to the inbound endpoint when the module owns the security group (for example the org supernet and the on-premises ranges). Required when enable_resolver_endpoints is true and security_group_ids is empty."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for c in var.allowed_cidrs : can(cidrnetmask(c))])
    error_message = "allowed_cidrs entries must be IPv4 CIDR blocks."
  }

  validation {
    condition     = !var.enable_resolver_endpoints || length(var.security_group_ids) > 0 || length(var.allowed_cidrs) > 0
    error_message = "allowed_cidrs must not be empty when enable_resolver_endpoints is true and security_group_ids is empty: the module-owned security group would admit no DNS."
  }
}

variable "forward_rules" {
  description = "FORWARD resolver rules keyed by rule name. Each rule forwards domain_name to target_ips via the outbound endpoint, is associated with the VPC and is added to the Route 53 Profile. Needs enable_resolver_endpoints = true."
  type = map(object({
    domain_name = string
    target_ips  = list(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = length(var.forward_rules) == 0 || var.enable_resolver_endpoints
    error_message = "forward_rules need the outbound endpoint: set enable_resolver_endpoints = true."
  }
}

variable "profile_hosted_zone_arns" {
  description = "Private hosted zones to add to the Route 53 Profile, keyed by a plan-known name. Every VPC that associates the profile resolves them."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "org_arn" {
  description = "AWS Organizations ARN granted access to the RAM share carrying the Route 53 Profile (org-wide DNS distribution)."
  type        = string

  validation {
    condition     = length(trimspace(var.org_arn)) > 0
    error_message = "org_arn must be a non-empty string."
  }
}

variable "enable_dns_firewall" {
  description = "Whether to create the DNS Firewall block list, rule group, BLOCK rule, VPC association, and fail-closed firewall config."
  type        = bool
  default     = true
}

variable "blocked_domains" {
  description = "Domains added to the DNS Firewall block list. Only used when enable_dns_firewall is true. Use FQDNs with a trailing dot (e.g. malware.example.)."
  type        = list(string)
  default     = ["malware.example."]
}

variable "enable_query_logging" {
  description = "Whether to create the resolver query log config and associate it with the VPC, shipping DNS queries to the central Log Archive."
  type        = bool
  default     = true
}

variable "query_log_destination_arn" {
  description = "ARN of the destination (S3 bucket, CloudWatch log group, or Kinesis stream) that receives resolver query logs. Required when enable_query_logging is true."
  type        = string
  default     = null

  validation {
    # Query logging enabled with an empty destination silently ships logs
    # nowhere; require a destination whenever logging is on.
    condition     = !var.enable_query_logging || try(length(trimspace(var.query_log_destination_arn)) > 0, false)
    error_message = "query_log_destination_arn is required when enable_query_logging is true."
  }
}

variable "enable_dnssec" {
  description = "Whether to enable DNSSEC validation for the VPC."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every taggable resource this module creates (merged after provider default_tags; resource-specific tags such as Name win)."
  type        = map(string)
  default     = {}
  nullable    = false
}
