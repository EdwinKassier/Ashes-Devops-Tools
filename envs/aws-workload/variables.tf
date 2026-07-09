# -----------------------------------------------------------------------------
# Terraform Cloud + cross-root wiring
# -----------------------------------------------------------------------------

variable "tfc_organization" {
  description = "Terraform Cloud organization that owns this root's workspace and the aws-organization + aws-network workspaces it reads. Supplied to the backend via backend.hcl / TF_CLI_ARGS_init (kept out of the code so the same root works across orgs and CI)."
  type        = string
  default     = null
}

variable "organization_workspace_name" {
  description = "Name of the Terraform Cloud workspace holding the phase-1 aws-organization root state that this root reads account_role_arns from."
  type        = string
  default     = "aws-organization"
}

variable "network_workspace_name" {
  description = "Name of the Terraform Cloud workspace holding the phase-2 aws-network root state that this root reads the network cross-root contract (tgw_id, ipam_pool_ids) from."
  type        = string
  default     = "aws-network"
}

variable "workload_account_key" {
  description = "Key into the aws-organization root's account_role_arns map identifying THIS environment's workload account (e.g. \"workload_dev\"). Both the default and us_east_1 providers assume that role."
  type        = string

  validation {
    condition     = length(trimspace(var.workload_account_key)) > 0
    error_message = "workload_account_key must be a non-empty account_role_arns map key."
  }
}

# -----------------------------------------------------------------------------
# Region + addressing
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region the workload's spoke VPC is deployed in and the region the default provider assumes the workload-account role in. Also the key used to select the regional IPAM pool from the aws-network contract."
  type        = string
  default     = "eu-west-2"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[1-9][0-9]?$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name, e.g. eu-west-2."
  }
}

variable "aws_enabled_regions" {
  description = "Regions in which to enforce the account baseline and deploy a Config recorder. Defaults to the single home Region."
  type        = list(string)
  default     = ["eu-west-2"]

  validation {
    condition     = length(var.aws_enabled_regions) > 0
    error_message = "aws_enabled_regions must contain at least one region."
  }
}

variable "vpc_cidr" {
  description = "IPv4 CIDR of the workload spoke VPC. Used for subnet math; the actual CIDR is allocated from the shared IPAM pool at apply."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block (e.g. 10.20.0.0/16)."
  }
}

# -----------------------------------------------------------------------------
# Log-archive naming contract + Config + KMS + toggles
# -----------------------------------------------------------------------------

variable "log_archive_bucket_name" {
  description = "Deterministic name of the central log-archive bucket that receives this workload's VPC flow logs, Config snapshots/history, and Session Manager session logs. Cross-root naming contract: it MUST match the name the aws-organization and aws-network roots use."
  type        = string

  validation {
    condition     = length(trimspace(var.log_archive_bucket_name)) > 0
    error_message = "log_archive_bucket_name must be a non-empty S3 bucket name."
  }
}

variable "config_role_arn" {
  description = "ARN of the IAM role AWS Config assumes to record resource configurations in this workload account/Region."
  type        = string

  validation {
    condition     = length(trimspace(var.config_role_arn)) > 0
    error_message = "config_role_arn must be a non-empty IAM role ARN."
  }
}

variable "kms_key_arn" {
  description = "ARN of the CMK used as the account default EBS encryption key and to encrypt Session Manager sessions/logs. Empty string leaves default EBS encryption on the AWS-managed key."
  type        = string
  default     = ""
}

variable "enable_edge" {
  description = "Deploy the per-workload edge-security stack (CloudFront + WAF, in us-east-1). Off by default; opt in when this environment fronts an internet-facing app."
  type        = bool
  default     = false
}

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
