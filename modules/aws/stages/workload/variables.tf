# -----------------------------------------------------------------------------
# Region + addressing
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region the workload's spoke VPC is deployed in and the region the default provider operates in. Used for subnet math and gateway-endpoint service names."
  type        = string
  default     = "eu-west-2"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region id (e.g. eu-west-2)."
  }
}

variable "aws_enabled_regions" {
  description = "Regions in which to enforce the account baseline (default EBS encryption) and deploy a Config recorder. Defaults to the single home Region."
  type        = list(string)
  default     = ["eu-west-2"]

  validation {
    condition     = length(var.aws_enabled_regions) > 0
    error_message = "aws_enabled_regions must contain at least one region."
  }
}

variable "vpc_cidr" {
  description = "IPv4 CIDR of the workload spoke VPC. Used for subnet math; also the literal VPC CIDR when ipam_pool_id is empty."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block (e.g. 10.20.0.0/16)."
  }
}

variable "ipam_pool_id" {
  description = "IPAM pool ID to allocate the spoke VPC CIDR from (the network account's regional pool, shared over RAM). Empty string uses the literal vpc_cidr instead."
  type        = string
  default     = ""
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

variable "subnets" {
  description = "Spoke subnet tiers, keyed by tier name. newbits/number_offset drive cidrsubnet(vpc_cidr, newbits, number_offset + az_index); the tgw tier holds the transit-gateway attachment ENIs. Offsets are multiples of 8 (> az_count) so per-AZ subnets never collide."
  type = map(object({
    newbits       = number
    number_offset = number
    public        = optional(bool, false)
  }))
  default = {
    private  = { newbits = 8, number_offset = 0 }
    isolated = { newbits = 8, number_offset = 8 }
    tgw      = { newbits = 8, number_offset = 16 }
  }

  validation {
    condition     = contains(keys(var.subnets), "tgw")
    error_message = "subnets must define a tgw tier for the transit-gateway attachment."
  }
}

# -----------------------------------------------------------------------------
# Shared-network wiring (from the aws-network root's cross-root contract)
# -----------------------------------------------------------------------------

variable "tgw_id" {
  description = "ID of the SHARED transit gateway (shared into this workload account over RAM by the network account) that the spoke VPC attaches to."
  type        = string

  validation {
    condition     = can(regex("^tgw-", var.tgw_id))
    error_message = "tgw_id must be a transit gateway id (tgw-xxxxxxxx)."
  }
}

variable "flow_log_destination_arn" {
  description = "ARN of the central log-archive S3 bucket that receives the spoke VPC's flow logs."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:s3:::", var.flow_log_destination_arn))
    error_message = "flow_log_destination_arn must be an S3 bucket ARN beginning with arn:aws:s3:::."
  }
}

# -----------------------------------------------------------------------------
# Config recorder + logging + KMS
# -----------------------------------------------------------------------------

variable "log_archive_bucket_name" {
  description = "Name of the central log-archive S3 bucket that receives Config snapshots/history and Session Manager session logs."
  type        = string

  validation {
    condition     = length(trimspace(var.log_archive_bucket_name)) > 0
    error_message = "log_archive_bucket_name must be a non-empty S3 bucket name."
  }
}

variable "config_role_arn" {
  description = "ARN of the IAM role AWS Config assumes to record resource configurations in this account/Region."
  type        = string

  validation {
    condition     = length(trimspace(var.config_role_arn)) > 0
    error_message = "config_role_arn must be a non-empty IAM role ARN."
  }
}

variable "kms_key_arn" {
  description = "ARN of the CMK used as the account default EBS encryption key and (when enable_ssm is true) to encrypt Session Manager sessions/logs. Empty string leaves default EBS encryption on the AWS-managed key; must be a non-empty key when enable_ssm is true."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# IAM roles
# -----------------------------------------------------------------------------

variable "workload_roles" {
  description = "Map of workload / cross-account IAM role name to its configuration (trust_policy JSON, managed_policy_arns, inline_policy, etc.). Empty by default."
  type = map(object({
    trust_policy         = string
    max_session_duration = optional(number, 3600)
    managed_policy_arns  = optional(list(string), [])
    inline_policy        = optional(string, "")
    permissions_boundary = optional(string)
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# Optional components
# -----------------------------------------------------------------------------

variable "enable_ssm" {
  description = "Deploy the Systems Manager baseline (Session Manager preferences, patch baseline, inventory). On by default. Requires a non-empty kms_key_arn (Session Manager sessions/logs are KMS-encrypted; an empty key would leave the session document's kmsKeyId blank)."
  type        = bool
  default     = true

  validation {
    # Guardrail: enabling SSM with an empty kms_key_arn would produce a Session
    # Manager document with an empty kmsKeyId, i.e. sessions NOT encrypted in
    # transit (CKV_AWS_112). Require a real CMK whenever SSM is on.
    condition     = !var.enable_ssm || length(trimspace(var.kms_key_arn)) > 0
    error_message = "kms_key_arn must be a non-empty CMK ARN when enable_ssm is true (Session Manager sessions must be KMS-encrypted)."
  }
}

variable "enable_edge" {
  description = "Deploy the per-workload edge-security stack (CloudFront + WAF, in us-east-1). Off by default; a workload opts in when it fronts an internet-facing app."
  type        = bool
  default     = false
}

variable "edge_name_prefix" {
  description = "Prefix applied to the edge WAF Web ACL, CloudFront Shield protection, and metric names. Ignored when enable_edge is false."
  type        = string
  default     = "workload-edge"

  validation {
    condition     = length(trimspace(var.edge_name_prefix)) > 0
    error_message = "edge_name_prefix must be a non-empty string."
  }
}

variable "edge_origin_domain_name" {
  description = "DNS name of the origin the edge CloudFront distribution fetches from. Ignored when enable_edge is false."
  type        = string
  default     = "origin.example.com"
}
