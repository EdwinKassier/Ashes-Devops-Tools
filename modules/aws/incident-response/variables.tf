variable "enable_incident_response" {
  description = "Master switch for the incident-response automation. When false, no Lambda, EventBridge rule, or forensics role is created."
  type        = bool
  default     = true
}

variable "forensics_account_id" {
  description = "12-digit AWS account ID of the forensics account that is trusted to assume the snapshot-sharing role. Required when enable_incident_response is true."
  type        = string
  default     = ""

  validation {
    # Empty is allowed only while incident response is disabled; when enabled a
    # valid 12-digit account id is required.
    condition     = !var.enable_incident_response || can(regex("^[0-9]{12}$", var.forensics_account_id))
    error_message = "forensics_account_id must be a 12-digit AWS account ID when enable_incident_response is true."
  }
}

variable "org_id" {
  description = "AWS Organizations organization ID (o-xxxx) used to scope the forensics role trust policy via aws:PrincipalOrgID."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_incident_response || can(regex("^o-[a-z0-9]{10,32}$", var.org_id))
    error_message = "org_id must be a valid AWS Organizations id (o-xxxxxxxxxx) when enable_incident_response is true."
  }
}
