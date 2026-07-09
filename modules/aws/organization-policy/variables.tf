# -----------------------------------------------------------------------------
# Organization identity + perimeter inputs
# -----------------------------------------------------------------------------

variable "org_id" {
  description = "AWS Organizations organization ID (o-xxxxxxxxxx). Used as the org-identity anchor in the RCP data-perimeter policy."
  type        = string

  validation {
    condition     = can(regex("^o-[a-z0-9]{10,32}$", var.org_id))
    error_message = "org_id must be an AWS Organizations org ID of the form o-xxxxxxxxxx."
  }
}

variable "allowed_regions" {
  description = "Regions permitted by the region-restriction SCP. Requests to any other region are denied (global services are carved out)."
  type        = list(string)
  default     = ["eu-west-2", "eu-west-1"]

  validation {
    condition     = length(var.allowed_regions) > 0
    error_message = "allowed_regions must contain at least one region."
  }
}

# -----------------------------------------------------------------------------
# Carve-out principals — must be account-qualified exact ARNs (no ::*:: wildcards)
# -----------------------------------------------------------------------------

variable "terraform_run_role_arn" {
  description = "Account-qualified exact ARN of the Terraform Cloud run role. Carved out of every deny statement so automation is not locked out."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", var.terraform_run_role_arn))
    error_message = "terraform_run_role_arn must be an account-qualified IAM role ARN (arn:aws:iam::<12-digit>:role/...)."
  }
}

variable "break_glass_role_arn" {
  description = "Account-qualified exact ARN of the emergency break-glass role. Carved out of every deny statement."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", var.break_glass_role_arn))
    error_message = "break_glass_role_arn must be an account-qualified IAM role ARN (arn:aws:iam::<12-digit>:role/...)."
  }
}

variable "log_archive_bucket_name" {
  description = "Name of the central log-archive S3 bucket protected from Object Lock / governance-retention tampering by the deny-tamper SCP."
  type        = string

  validation {
    condition     = length(trimspace(var.log_archive_bucket_name)) > 0
    error_message = "log_archive_bucket_name must be a non-empty S3 bucket name."
  }
}

variable "default_region" {
  description = "Region used by the backup policy's default plan."
  type        = string
  default     = "eu-west-2"
}

# -----------------------------------------------------------------------------
# Policy set + attachments
# -----------------------------------------------------------------------------

variable "policies" {
  description = "Override map of policies to create, keyed by policy name. When empty (default), the module computes the built-in guardrail set from the templated JSON files. Content is a raw Organizations policy JSON string."
  type = map(object({
    type    = string
    content = string
  }))
  default = {}

  validation {
    condition = alltrue([
      for p in values(var.policies) : contains(
        ["SERVICE_CONTROL_POLICY", "RESOURCE_CONTROL_POLICY", "DECLARATIVE_POLICY_EC2", "TAG_POLICY", "BACKUP_POLICY", "AISERVICES_OPT_OUT_POLICY", "CHATBOT_POLICY", "SECURITYHUB_POLICY"],
        p.type
      )
    ])
    error_message = "Each policy type must be a valid AWS Organizations policy type."
  }
}

variable "attachments" {
  description = "Policy attachments binding a policy_key (name in the effective policy set) to a target OU root/OU/account ID. Keyed by a stable caller-chosen string so for_each stays known at plan time even when target_id is a computed root/OU ID."
  type = map(object({
    policy_key = string
    target_id  = string
  }))
  default = {}
}
