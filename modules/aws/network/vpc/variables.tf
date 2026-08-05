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
  description = "IPv4 CIDR used for subnet math (cidrsubnet). Also the literal VPC CIDR when ipam_pool_id is empty. When using IPAM, still set this to the CIDR IPAM will allocate so subnet layout is deterministic."
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
  description = "IPAM pool ID to allocate the VPC CIDR from. Empty string uses the literal cidr_block instead."
  type        = string
  default     = ""
}

variable "netmask_length" {
  description = "Netmask length requested from the IPAM pool when ipam_pool_id is set. Ignored when using a literal cidr_block."
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
  default     = "eu-west-2"

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
    condition     = can(regex("^arn:aws:s3:::", var.flow_log_destination_arn))
    error_message = "flow_log_destination_arn must be an S3 bucket ARN beginning with arn:aws:s3:::."
  }
}

variable "gateway_endpoints" {
  description = "AWS services to create Gateway VPC endpoints for (e.g. s3, dynamodb)."
  type        = list(string)
  default     = ["s3", "dynamodb"]
}
