# -----------------------------------------------------------------------------
# Gate
# -----------------------------------------------------------------------------

variable "enable_private_ca" {
  description = "Master switch for the module. When false, no resources are created. ACM Private CA bills a fixed monthly charge per CA from creation, so this defaults to false — enable it deliberately."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Certificate authority configuration
# -----------------------------------------------------------------------------

variable "ca_type" {
  description = "Type of certificate authority. ROOT anchors the hierarchy; SUBORDINATE is signed by a parent CA."
  type        = string
  default     = "ROOT"

  validation {
    condition     = contains(["ROOT", "SUBORDINATE"], var.ca_type)
    error_message = "ca_type must be either ROOT or SUBORDINATE."
  }
}

variable "key_algorithm" {
  description = "Key algorithm used to generate the CA's key pair (e.g. RSA_4096, EC_prime256v1)."
  type        = string
  default     = "RSA_4096"
}

variable "signing_algorithm" {
  description = "Algorithm the CA uses to sign certificates it issues (e.g. SHA512WITHRSA)."
  type        = string
  default     = "SHA512WITHRSA"
}

variable "common_name" {
  description = "Common name (CN) placed in the CA certificate subject."
  type        = string
  default     = "org-internal-ca"
}

variable "permanent_deletion_time_in_days" {
  description = "Number of days AWS retains a deleted CA before permanent destruction (recovery window). Must be between 7 and 30."
  type        = number
  default     = 7

  validation {
    condition     = var.permanent_deletion_time_in_days >= 7 && var.permanent_deletion_time_in_days <= 30
    error_message = "permanent_deletion_time_in_days must be between 7 and 30."
  }
}

# -----------------------------------------------------------------------------
# Organization RAM sharing
# -----------------------------------------------------------------------------

variable "share_org" {
  description = "Whether to share the CA across the AWS organization via RAM so member accounts can issue certificates from it."
  type        = bool
  default     = true
}

variable "share_name" {
  description = "Name of the RAM resource share created when share_org is true."
  type        = string
  default     = "private-ca-share"
}

variable "org_arn" {
  description = "ARN of the AWS organization (or an OU) granted access to the RAM share. Required when share_org is true."
  type        = string
  default     = ""
}
