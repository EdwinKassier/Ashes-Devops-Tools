# -----------------------------------------------------------------------------
# Organizational unit topology
# -----------------------------------------------------------------------------

variable "top_level_ous" {
  description = "Names of the top-level organizational units created directly under the org root. Defaults to the AWS SRA foundational OU set."
  type        = list(string)
  default     = ["Security", "Infrastructure", "Workloads", "Sandbox", "Suspended", "PolicyStaging", "Exceptions", "Transitional"]

  validation {
    condition     = length(var.top_level_ous) > 0
    error_message = "top_level_ous must contain at least one OU name."
  }

  validation {
    # Reject empty/whitespace-only OU names; AWS requires a non-blank OU name.
    condition     = alltrue([for name in var.top_level_ous : length(trimspace(name)) > 0])
    error_message = "Every entry in top_level_ous must be a non-empty OU name."
  }

  validation {
    condition     = length(var.top_level_ous) == length(distinct(var.top_level_ous))
    error_message = "top_level_ous must not contain duplicate names."
  }
}

variable "child_ous" {
  description = "Child organizational units nested under a top-level OU. Each parent must appear in top_level_ous."
  type = list(object({
    parent = string # Name of the top-level OU this child is nested under (must be in top_level_ous)
    name   = string # Name of the child OU
  }))
  default = [
    { parent = "Workloads", name = "Prod" },
    { parent = "Workloads", name = "NonProd" },
  ]

  validation {
    condition     = alltrue([for c in var.child_ous : length(trimspace(c.name)) > 0 && length(trimspace(c.parent)) > 0])
    error_message = "Every child_ous entry must have a non-empty parent and name."
  }

  validation {
    # The child for_each keys on "parent/name"; duplicates would collide.
    condition     = length(var.child_ous) == length(distinct([for c in var.child_ous : "${c.parent}/${c.name}"]))
    error_message = "Each child OU (parent/name pair) must be unique."
  }
}

# -----------------------------------------------------------------------------
# Organization policy + trusted-service configuration
# -----------------------------------------------------------------------------

variable "enabled_policy_types" {
  description = "Organization policy types to enable at the root. Requires feature_set = ALL."
  type        = list(string)
  default     = ["SERVICE_CONTROL_POLICY", "RESOURCE_CONTROL_POLICY", "DECLARATIVE_POLICY_EC2", "TAG_POLICY", "BACKUP_POLICY"]

  validation {
    condition = alltrue([
      for t in var.enabled_policy_types : contains(
        ["SERVICE_CONTROL_POLICY", "RESOURCE_CONTROL_POLICY", "DECLARATIVE_POLICY_EC2", "TAG_POLICY", "BACKUP_POLICY", "AISERVICES_OPT_OUT_POLICY", "CHATBOT_POLICY", "SECURITYHUB_POLICY"],
        t
      )
    ])
    error_message = "enabled_policy_types entries must be valid AWS Organizations policy types."
  }
}

variable "aws_service_access_principals" {
  description = "AWS service principals granted trusted access to the organization (enables delegated administration for SRA security services)."
  type        = list(string)
  default = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "config-multiaccountsetup.amazonaws.com",
    "guardduty.amazonaws.com",
    "securityhub.amazonaws.com",
    "access-analyzer.amazonaws.com",
    "malware-protection.guardduty.amazonaws.com",
    "macie.amazonaws.com",
    "inspector2.amazonaws.com",
    "detective.amazonaws.com",
    "ram.amazonaws.com",
    "sso.amazonaws.com",
    "ipam.amazonaws.com",
    "iam.amazonaws.com",
    "ssm.amazonaws.com",
    "resource-explorer-2.amazonaws.com",
    "fms.amazonaws.com",
    "backup.amazonaws.com",
    "securitylake.amazonaws.com",
  ]

  validation {
    condition     = alltrue([for p in var.aws_service_access_principals : can(regex("[.]amazonaws[.]com$", p))])
    error_message = "Each service access principal must be an AWS service principal ending in .amazonaws.com."
  }
}
