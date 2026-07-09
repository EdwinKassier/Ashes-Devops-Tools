# -----------------------------------------------------------------------------
# Gate
# -----------------------------------------------------------------------------

variable "enable_secrets_baseline" {
  description = "Master switch for the module. When false, no secrets, policies, or rotations are created."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Secrets
# -----------------------------------------------------------------------------

variable "secrets" {
  description = "Map of secret name to its configuration. rotation_lambda_arn, when set, enables automatic rotation for that secret; rotation_days controls the rotation interval."
  type = map(object({
    rotation_lambda_arn = optional(string, "")
    rotation_days       = optional(number, 30)
  }))
  default = {}
}

variable "kms_key_id" {
  description = "ARN or ID of a customer-managed KMS key used to encrypt all secrets. When empty, secrets use the account default aws/secretsmanager managed key."
  type        = string
  default     = ""
}

variable "org_id" {
  description = "AWS organization ID (o-xxxxxxxxxx) used in the aws:PrincipalOrgID condition that scopes secret access to the organization. Required when enable_secrets_baseline is true."
  type        = string
  default     = ""

  validation {
    # When the module is enabled the org_id feeds the aws:PrincipalOrgID
    # condition; an empty/malformed value silently produces an ineffective
    # resource policy, so require a valid o-xxxx id whenever enabled.
    condition     = !var.enable_secrets_baseline || can(regex("^o-[a-z0-9]+$", var.org_id))
    error_message = "org_id must be a valid o-xxxx org id when enable_secrets_baseline is true."
  }
}
