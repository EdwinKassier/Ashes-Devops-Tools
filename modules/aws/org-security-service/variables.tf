variable "enabled_services" {
  description = "Set of org-security services to enable. Each enables a gated block: macie, inspector, detective, resource-explorer. Detective defaults OFF per SRA. Adding a service means adding a gated block in main.tf and a name to this allowed set."
  type        = set(string)
  default     = ["macie", "inspector"]

  validation {
    condition = alltrue([
      for s in var.enabled_services : contains(["macie", "inspector", "detective", "resource-explorer"], s)
    ])
    error_message = "enabled_services entries must be one of: macie, inspector, detective, resource-explorer."
  }
}

variable "security_tooling_account_id" {
  description = "12-digit account ID of the Security Tooling account nominated as the delegated administrator (the module's default provider). Used as the admin/account ID in the management-account registrations."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.security_tooling_account_id))
    error_message = "security_tooling_account_id must be a 12-digit AWS account ID."
  }
}
