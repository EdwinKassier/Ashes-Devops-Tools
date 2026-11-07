variable "registrations" {
  description = "Explicit map of AWS service principal to the account ID nominated as that service's delegated administrator. When non-empty this overrides the convenience default built from security_tooling_account_id and identity_account_id. Do NOT include services that have a dedicated admin resource (guardduty, macie, inspector, detective, securityhub) — they are registered elsewhere."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for id in values(var.registrations) : can(regex("^[0-9]{12}$", id))])
    error_message = "Every account ID in registrations must be a 12-digit AWS account ID."
  }

  validation {
    condition     = alltrue([for p in keys(var.registrations) : can(regex("[.]amazonaws[.]com$", p))])
    error_message = "Every registrations key must be an AWS service principal ending in .amazonaws.com."
  }
}

variable "security_tooling_account_id" {
  description = "12-digit account ID of the Security Tooling account, used as the delegated administrator for the security services in the default registration set (Access Analyzer, Backup, Config, CloudTrail, FMS, SSM, Resource Explorer, Security Lake). Ignored when registrations is non-empty."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.security_tooling_account_id))
    error_message = "security_tooling_account_id must be a 12-digit AWS account ID."
  }
}

variable "identity_account_id" {
  description = "12-digit account ID of the Identity account, used as the delegated administrator for IAM Identity Center (sso.amazonaws.com) in the default registration set. Ignored when registrations is non-empty."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.identity_account_id))
    error_message = "identity_account_id must be a 12-digit AWS account ID."
  }
}

variable "register_identity_center_admin" {
  description = "Also register identity_account_id as the IAM Identity Center (sso.amazonaws.com) delegated administrator. Default false: aws-organization owns that registration, so the aws-security pipeline cannot hand identity control to an arbitrary account."
  type        = bool
  default     = false
}

variable "register_cloudtrail_admin" {
  description = "Register security_tooling_account_id as the cloudtrail.amazonaws.com delegated administrator here, through the generic Organizations API (default set only). Set false when aws-organization registers it through CloudTrail (enable_cloudtrail_delegated_admin). Default true: unchanged."
  type        = bool
  default     = true
  nullable    = false
}

variable "backup_account_id" {
  description = "12-digit account ID of the dedicated backup account, registered as the AWS Backup delegated administrator. Null = security_tooling_account_id."
  type        = string
  default     = null

  validation {
    condition     = var.backup_account_id == null || can(regex("^[0-9]{12}$", coalesce(var.backup_account_id, "x")))
    error_message = "backup_account_id must be a 12-digit AWS account ID."
  }
}
