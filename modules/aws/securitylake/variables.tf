variable "enable_security_lake" {
  description = "Master COST toggle for Amazon Security Lake. When false the module creates no resources. Security Lake incurs ingestion, storage, and normalization charges, so it is gated separately from the rest of the security tooling."
  type        = bool
  default     = true
}

variable "meta_store_manager_role_arn" {
  description = "ARN of the AmazonSecurityLakeMetaStoreManager IAM role used by Security Lake to manage the Lake Formation metastore. Required when enable_security_lake is true."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_security_lake || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.meta_store_manager_role_arn))
    error_message = "meta_store_manager_role_arn must be a valid IAM role ARN when enable_security_lake is true."
  }
}

variable "kms_key_id" {
  description = "KMS key identifier (key ID, ARN, or the literal S3_MANAGED) used to encrypt the Security Lake S3 objects in each configured Region."
  type        = string
  default     = "S3_MANAGED"

  validation {
    condition     = length(trimspace(var.kms_key_id)) > 0
    error_message = "kms_key_id must be a non-empty KMS key identifier, ARN, or S3_MANAGED."
  }
}

variable "aws_enabled_regions" {
  description = "Regions in which Security Lake is enabled. One data-lake configuration block is created per Region."
  type        = list(string)
  default     = ["eu-west-2"]

  validation {
    condition     = length(var.aws_enabled_regions) > 0
    error_message = "aws_enabled_regions must contain at least one Region."
  }
}

variable "log_sources" {
  description = "AWS-native log sources ingested into Security Lake. Each must be one of CLOUD_TRAIL_MGMT, VPC_FLOW, ROUTE53, or SH_FINDINGS."
  type        = list(string)
  default     = ["CLOUD_TRAIL_MGMT", "VPC_FLOW", "ROUTE53", "SH_FINDINGS"]

  validation {
    condition = alltrue([
      for s in var.log_sources : contains(["CLOUD_TRAIL_MGMT", "VPC_FLOW", "ROUTE53", "SH_FINDINGS"], s)
    ])
    error_message = "Each log_sources entry must be one of CLOUD_TRAIL_MGMT, VPC_FLOW, ROUTE53, or SH_FINDINGS."
  }
}

variable "subscriber_name" {
  description = "Name of the optional Security Lake subscriber. Only used when subscriber_principal is set."
  type        = string
  default     = "security-tooling"

  validation {
    condition     = length(trimspace(var.subscriber_name)) > 0
    error_message = "subscriber_name must be a non-empty string."
  }
}

variable "subscriber_principal" {
  description = "AWS account ID (12 digits) of the subscriber principal granted read access to the OCSF data. When empty, no subscriber is created."
  type        = string
  default     = ""

  validation {
    condition     = var.subscriber_principal == "" || can(regex("^[0-9]{12}$", var.subscriber_principal))
    error_message = "subscriber_principal must be empty or a 12-digit AWS account ID."
  }
}

variable "subscriber_external_id" {
  description = "External ID used in the subscriber identity trust condition."
  type        = string
  default     = "securitylake"

  validation {
    condition     = length(trimspace(var.subscriber_external_id)) > 0
    error_message = "subscriber_external_id must be a non-empty string."
  }
}
