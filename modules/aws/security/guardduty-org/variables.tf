variable "aws_enabled_regions" {
  description = "Regions in which to enable org-wide GuardDuty. A detector, org configuration and protection-plan features are created in each."
  type        = list(string)
  default     = ["eu-west-2"]

  validation {
    condition     = length(var.aws_enabled_regions) > 0
    error_message = "aws_enabled_regions must contain at least one Region."
  }

  validation {
    condition     = length(var.aws_enabled_regions) == length(distinct(var.aws_enabled_regions))
    error_message = "aws_enabled_regions must not contain duplicate Regions."
  }
}

variable "security_tooling_account_id" {
  description = "12-digit account ID of the Security Tooling account nominated as the GuardDuty delegated administrator (the module's default provider)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.security_tooling_account_id))
    error_message = "security_tooling_account_id must be a 12-digit AWS account ID."
  }
}

variable "enable_ebs_malware_protection" {
  description = "Enable the EBS_MALWARE_PROTECTION feature. COST toggle: agentless EBS malware scanning is billed per GB scanned, so it defaults on but can be disabled."
  type        = bool
  default     = true
}
