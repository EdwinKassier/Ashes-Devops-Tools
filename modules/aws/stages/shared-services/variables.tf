# -----------------------------------------------------------------------------
# ACM Private CA
# -----------------------------------------------------------------------------

variable "enable_private_ca" {
  description = "Master switch for the ACM Private CA capability. When false, no CA (and no RAM share) is created. ACM PCA bills a fixed monthly charge per CA from creation, so this defaults to false — enable it deliberately."
  type        = bool
  default     = false
}

variable "ca_type" {
  description = "Type of certificate authority. ROOT anchors the hierarchy; SUBORDINATE is signed by a parent CA."
  type        = string
  default     = "ROOT"

  validation {
    condition     = contains(["ROOT", "SUBORDINATE"], var.ca_type)
    error_message = "ca_type must be either ROOT or SUBORDINATE."
  }
}

variable "ca_common_name" {
  description = "Common name (CN) placed in the CA certificate subject."
  type        = string
  default     = "org-internal-ca"
}

variable "share_ca_org" {
  description = "Whether to share the CA across the AWS organization via RAM so member accounts can issue certificates from it. Requires org_arn when true."
  type        = bool
  default     = true
}

variable "org_arn" {
  description = "ARN of the AWS Organization (arn:aws:organizations::<mgmt-account>:organization/o-xxxx) granted access to the CA's RAM share. Required when both enable_private_ca and share_ca_org are true."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Secrets Manager baseline
# -----------------------------------------------------------------------------

variable "enable_secrets_baseline" {
  description = "Master switch for the Secrets Manager baseline capability. When false, no secrets, policies, or rotations are created."
  type        = bool
  default     = false
}

variable "secrets" {
  description = "Map of secret name to its configuration. rotation_lambda_arn, when set, enables automatic rotation for that secret; rotation_days controls the rotation interval."
  type = map(object({
    rotation_lambda_arn = optional(string, "")
    rotation_days       = optional(number, 30)
  }))
  default = {}
}

variable "secrets_kms_key_id" {
  description = "ARN or ID of a customer-managed KMS key used to encrypt all secrets. When empty, secrets use the account default aws/secretsmanager managed key."
  type        = string
  default     = ""
}

variable "org_id" {
  description = "AWS organization ID (o-xxxxxxxxxx) used in the aws:PrincipalOrgID condition that scopes secret access to the organization. Required when enable_secrets_baseline is true."
  type        = string
  default     = ""
}
