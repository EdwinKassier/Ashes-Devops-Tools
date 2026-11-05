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
  description = "Name of the central log-archive bucket (receives this workload's VPC flow logs, Config snapshots/history, and Session Manager logs). Default null sources it from the aws-security root's remote state (its owner — see audit M7), so a rename there flows through automatically. Set a value only to override for an out-of-band setup."
  type        = string
  default     = null

  validation {
    condition     = var.log_archive_bucket_name == null || length(trimspace(coalesce(var.log_archive_bucket_name, " "))) > 0
    error_message = "log_archive_bucket_name must be null (source from aws-security) or a non-empty S3 bucket name."
  }
}

variable "security_workspace_name" {
  description = "Name of the aws-security TFC workspace, read via remote state for the central log-archive bucket name (audit M7)."
  type        = string
  default     = "aws-security"
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

# -----------------------------------------------------------------------------
# SaaS secret bridge (audit H9, hybrid option C) — AWS counterpart to the GCP one.
#
# Opt-in. When enabled, this workload reads the Supabase outputs from a saas-<name>
# workspace and writes them into an AWS Secrets Manager secret, so an ECS/Fargate
# task can consume Supabase as a managed datastore via the container secrets
# valueFrom. Default off: no SaaS coupling, and the workload reads no saas state.
#
# NOTE: the bridged values (service role key, database password) are stored as a
# secret version, so they persist in THIS root's state as well as the saas root's.
# Teams that require zero secret duplication should create the secret out of band
# and leave this bridge disabled.
# -----------------------------------------------------------------------------

variable "enable_saas_secret_bridge" {
  description = "Bridge Supabase connection details from a saas-<name> workspace into an AWS Secrets Manager secret (opt-in, audit H9). Default false."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_saas_secret_bridge || (var.saas_workspace_name != null && length(var.saas_secret_reader_arns) > 0)
    error_message = "enable_saas_secret_bridge = true requires saas_workspace_name and at least one saas_secret_reader_arns entry (the task role that reads the secret)."
  }
}

variable "saas_workspace_name" {
  description = "TFC workspace (saas-<name>) to read Supabase outputs from when enable_saas_secret_bridge is true."
  type        = string
  default     = null
}

variable "saas_secret_name" {
  description = "Name of the Secrets Manager secret that holds the bridged Supabase connection JSON (api_url, service_role_key, database_password)."
  type        = string
  default     = "supabase-connection"

  validation {
    condition     = can(regex("^[a-zA-Z0-9/_+=.@-]{1,512}$", var.saas_secret_name))
    error_message = "saas_secret_name must be a valid Secrets Manager name (1-512 chars of alphanumerics and /_+=.@-)."
  }
}

variable "saas_secret_reader_arns" {
  description = "IAM principal ARNs granted secretsmanager:GetSecretValue on the bridged secret (e.g. the ECS task role). Required when the bridge is enabled."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.saas_secret_reader_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:", a))])
    error_message = "Each saas_secret_reader_arns entry must be an account-qualified IAM ARN (arn:aws:iam::<12-digit>:...)."
  }
}
