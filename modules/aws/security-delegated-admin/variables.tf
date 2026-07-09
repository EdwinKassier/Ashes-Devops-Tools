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
  description = "12-digit account ID of the Security Tooling account, used as the delegated administrator for the security services in the default registration set (Access Analyzer, Config, CloudTrail, FMS, SSM, Resource Explorer, Security Lake). Ignored when registrations is non-empty."
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
