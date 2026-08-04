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
    condition     = can(regex("^arn:aws:organizations::", var.org_arn))
    error_message = "org_arn must be an AWS Organizations ARN beginning with arn:aws:organizations::."
  }
}

variable "aws_region" {
  description = "AWS region the network hub is deployed in. Used for the inspection/egress VPCs, gateway/interface endpoint service names, and NAT placement."
  type        = string
  default     = "eu-west-2"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
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
    condition     = var.az_count >= 1 && var.az_count <= 3
    error_message = "az_count must be between 1 and 3."
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
    condition     = can(regex("^arn:aws:s3:::", var.flow_log_destination_arn))
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

variable "enable_network_access_analyzer" {
  description = "Whether to create the Network Access Analyzer scope that flags segmentation-intent violations. Off by default."
  type        = bool
  default     = false
}
