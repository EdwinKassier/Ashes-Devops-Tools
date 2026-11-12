variable "vpc_id" {
  description = "ID of the central hub VPC that hosts the interface endpoints and the shared private hosted zone."
  type        = string

  validation {
    condition     = length(trimspace(var.vpc_id)) > 0
    error_message = "vpc_id must be a non-empty string."
  }
}

variable "region" {
  description = "AWS region, used to build interface endpoint service names (com.amazonaws.<region>.<service>)."
  type        = string

  validation {
    # Matches AWS region ids like eu-west-2, us-east-1, ap-southeast-3.
    condition     = can(regex("^[a-z]{2}-[a-z]+-[1-9][0-9]?$", var.region))
    error_message = "region must be a valid AWS region id (e.g. eu-west-2)."
  }
}

variable "subnet_ids" {
  description = "Subnet IDs (one per AZ, in the hub VPC) to place the interface endpoint ENIs in."
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "Security group IDs to associate with the interface endpoint ENIs. Empty (default) = a module-owned group that admits HTTPS from allowed_cidrs (when allowed_cidrs is set)."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "allowed_cidrs" {
  description = "CIDRs that may reach the interface endpoints on 443 when security_group_ids is empty (the module then owns the group). Use the org supernet for centralized endpoints. Empty with no security_group_ids = the VPC default security group."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for c in var.allowed_cidrs : can(cidrnetmask(c))])
    error_message = "allowed_cidrs entries must be IPv4 CIDR blocks."
  }
}

variable "enable_shared_private_dns" {
  description = "Serve each endpoint's regional name (<service>.<region>.amazonaws.com) from a private hosted zone with an alias record, instead of the endpoint's own private DNS, so other VPCs (through a Route 53 Profile) resolve the central endpoint. Only for services whose private DNS name is <service>.<region>.amazonaws.com. Default false."
  type        = bool
  default     = false
  nullable    = false
}

variable "interface_services" {
  description = "AWS services to create centralized Interface VPC endpoints for. Service names are built as com.amazonaws.<region>.<service>."
  type        = list(string)
  default     = ["ec2", "ssm", "ssmmessages", "ec2messages", "kms", "logs", "sts"]

  validation {
    condition     = length(var.interface_services) > 0
    error_message = "interface_services must contain at least one service."
  }
}

variable "org_id" {
  description = "AWS Organizations org id (o-xxxxxxxxxx) used in the endpoint policy aws:PrincipalOrgID condition to scope access to this organization."
  type        = string

  validation {
    condition     = length(trimspace(var.org_id)) > 0
    error_message = "org_id must be a non-empty string."
  }
}

variable "private_hosted_zone_name" {
  description = "Name of the shared Route 53 private hosted zone for split-horizon DNS. Empty string skips creating the zone."
  type        = string
  default     = ""
}

variable "endpoint_policy_json" {
  description = "Optional override for the interface-endpoint policy (a JSON document). When null (default), the module applies an org-scoped allow-all policy gated by aws:PrincipalOrgID and relies on IAM for authorization. Supply a scoped policy to enforce per-service least privilege on the shared endpoints."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every taggable resource this module creates (merged after provider default_tags; resource-specific tags such as Name win)."
  type        = map(string)
  default     = {}
  nullable    = false
}
