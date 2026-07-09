variable "aws_enabled_regions" {
  description = "Regions IPAM operates in. Each becomes an operating region on the IPAM and gets its own regional pool sourced from the top pool."
  type        = list(string)
  default     = ["eu-west-2"]

  validation {
    condition     = length(var.aws_enabled_regions) > 0
    error_message = "aws_enabled_regions must contain at least one region."
  }

  validation {
    condition     = length(var.aws_enabled_regions) == length(distinct(var.aws_enabled_regions))
    error_message = "aws_enabled_regions must not contain duplicate regions."
  }
}

variable "top_cidr" {
  description = "CIDR of the top-level supernet owned by the top IPAM pool. Regional pool CIDRs are carved from within this range."
  type        = string
  default     = "10.0.0.0/8"

  validation {
    # cidrhost fails on a malformed CIDR, so a successful call proves the value
    # parses as a valid CIDR block.
    condition     = can(cidrhost(var.top_cidr, 0))
    error_message = "top_cidr must be a valid IPv4 CIDR block (e.g. 10.0.0.0/8)."
  }
}

variable "regional_cidrs" {
  description = "Map of region to the CIDR each regional pool provisions. Every key should be a region present in aws_enabled_regions and every CIDR should fall within top_cidr."
  type        = map(string)
  default     = { eu-west-2 = "10.0.0.0/12" }

  validation {
    condition     = alltrue([for c in values(var.regional_cidrs) : can(cidrhost(c, 0))])
    error_message = "Every value in regional_cidrs must be a valid IPv4 CIDR block."
  }

  validation {
    # Every regional pool key must map to an operating region; a key not in
    # aws_enabled_regions would carve a pool with no IPAM operating region.
    condition     = alltrue([for k in keys(var.regional_cidrs) : contains(var.aws_enabled_regions, k)])
    error_message = "Every regional_cidrs key must be a region present in aws_enabled_regions."
  }
}

variable "share_name" {
  description = "Name of the AWS RAM resource share used to share the regional IPAM pools organization-wide."
  type        = string
  default     = "ipam-pools"

  validation {
    condition     = length(trimspace(var.share_name)) > 0
    error_message = "share_name must be a non-empty string."
  }
}

variable "org_arn" {
  description = "ARN of the AWS organization (arn:aws:organizations::<mgmt-account>:organization/o-xxxx) used as the RAM principal so the shared pools are available org-wide."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:organizations::", var.org_arn))
    error_message = "org_arn must be an AWS Organizations ARN beginning with arn:aws:organizations::."
  }
}

variable "description" {
  description = "Description applied to the IPAM."
  type        = string
  default     = "SRA landing zone hierarchical IPAM."
}
