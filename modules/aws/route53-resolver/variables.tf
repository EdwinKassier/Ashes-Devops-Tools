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
  description = "ID of the VPC that resolver rules, DNS firewall, query logging, DNSSEC, and the Route 53 Profile are associated with."
  type        = string

  validation {
    condition     = length(trimspace(var.vpc_id)) > 0
    error_message = "vpc_id must be a non-empty string."
  }
}

variable "subnet_ids" {
  description = "Subnet IDs the inbound and outbound resolver endpoints place IPs in. At least two are required (one per AZ) because the endpoint ip_address block enforces a minimum of two entries."
  type        = list(string)
  default     = ["subnet-aaaa", "subnet-bbbb"]

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids must contain at least two subnets (resolver endpoints require a minimum of two IP addresses)."
  }
}

variable "security_group_ids" {
  description = "Security group IDs attached to the inbound and outbound resolver endpoints. At least one is required by the resolver endpoint resource."
  type        = list(string)
  default     = ["sg-aaaaaaaaaaaaaaaaa"]

  validation {
    condition     = length(var.security_group_ids) >= 1
    error_message = "security_group_ids must contain at least one security group (resolver endpoints require a minimum of one)."
  }
}

variable "forward_rules" {
  description = "FORWARD resolver rules keyed by rule name. Each rule forwards domain_name to target_ips via the outbound endpoint and is associated with the VPC."
  type = map(object({
    domain_name = string
    target_ips  = list(string)
  }))
  default = {}
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
  default     = ""
}

variable "enable_dnssec" {
  description = "Whether to enable DNSSEC validation for the VPC."
  type        = bool
  default     = false
}
