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
  description = "AWS Organizations organization ID (o-xxxx) used to scope the forensics role trust policy via aws:PrincipalOrgID and the forensics KMS grant via aws:PrincipalOrgID."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_incident_response || can(regex("^o-[a-z0-9]{10,32}$", var.org_id))
    error_message = "org_id must be a valid AWS Organizations id (o-xxxxxxxxxx) when enable_incident_response is true."
  }
}

variable "quarantine_vpc_id" {
  description = "VPC ID in which the deny-all quarantine security group is created. Empty (default) skips the SG; supply the VPC that holds the workloads the isolation Lambda may need to quarantine. The Lambda attaches this SG to a flagged instance's ENIs to cut off all traffic."
  type        = string
  default     = ""

  validation {
    condition     = var.quarantine_vpc_id == "" || can(regex("^vpc-[0-9a-f]{8,17}$", var.quarantine_vpc_id))
    error_message = "quarantine_vpc_id must be empty or a valid VPC id of the form vpc-xxxxxxxx."
  }
}

variable "forensics_kms_key_arn" {
  description = "ARN of the forensics CMK. When set, the forensics snapshot-sharing role is granted kms:Decrypt/DescribeKey/CreateGrant on it (scoped by aws:PrincipalOrgID) so shared encrypted snapshots are usable in the forensics account. Empty (default) omits the grant."
  type        = string
  default     = ""

  validation {
    condition     = var.forensics_kms_key_arn == "" || can(regex("^arn:aws[a-z-]*:kms:", var.forensics_kms_key_arn))
    error_message = "forensics_kms_key_arn must be empty or a valid KMS key ARN."
  }
}

variable "permissions_boundary_arn" {
  description = "Permissions-boundary managed policy ARN set on every IAM role this module creates. Required when the roles are created by a member-account tfc-apply role with boundary propagation on (tfc-oidc-baseline enable_apply_boundary_propagation): pass arn:PARTITION:iam::ACCOUNT_ID:policy/tfc-apply-boundary. Null (default) = no boundary."
  type        = string
  default     = null

  validation {
    condition     = var.permissions_boundary_arn == null || can(regex("^arn:[^:]+:iam::[^:]*:policy/.+$", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be null or an IAM managed policy ARN (arn:PARTITION:iam::ACCOUNT_ID:policy/NAME)."
  }
}

variable "tags" {
  description = "Tags applied to every taggable resource this module creates (merged after provider default_tags; resource-specific tags such as Name win)."
  type        = map(string)
  default     = {}
  nullable    = false
}
