variable "security_tooling_account_id" {
  description = "12-digit account ID of the Security Tooling (MEMBER) account nominated as the Security Hub delegated administrator. Must NOT be the management account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.security_tooling_account_id))
    error_message = "security_tooling_account_id must be a 12-digit AWS account ID."
  }
}

variable "org_root_id" {
  description = "The organization root ID (r-xxxx) that the baseline configuration policy is associated with."
  type        = string

  validation {
    condition     = can(regex("^r-[0-9a-z]{4,32}$", var.org_root_id))
    error_message = "org_root_id must be an organization root ID of the form r-xxxx."
  }
}

variable "home_region" {
  description = "Home (aggregation) Region used to build the default region-scoped standard ARNs for enabled_standard_arns."
  type        = string
  default     = "eu-west-2"

  validation {
    condition     = length(trimspace(var.home_region)) > 0
    error_message = "home_region must be a non-empty Region name."
  }
}

variable "enabled_standard_arns" {
  description = "Security standard ARNs enabled by the baseline configuration policy. Defaults (when empty) to FSBP + CIS 1.4 + NIST 800-53 r5, built from home_region."
  type        = list(string)
  default     = []
}

variable "policy_name" {
  description = "Name of the Security Hub configuration policy."
  type        = string
  default     = "baseline"

  validation {
    condition     = length(trimspace(var.policy_name)) > 0
    error_message = "policy_name must be a non-empty string."
  }
}

variable "disabled_control_identifiers" {
  description = "Security control identifiers disabled org-wide by the baseline policy. Security Hub enables all other controls (including newly released ones)."
  type        = list(string)
  default     = []
}
