# -----------------------------------------------------------------------------
# Terraform Cloud + cross-root wiring
# -----------------------------------------------------------------------------

variable "tfc_organization" {
  description = "Terraform Cloud organization that owns this root's workspace and the aws-organization workspace it reads. Supplied to the backend via backend.hcl / TF_CLI_ARGS_init (kept out of the code so the same root works across orgs and CI)."
  type        = string
  default     = null
}

variable "organization_workspace_name" {
  description = "Name of the Terraform Cloud workspace holding the phase-1 aws-organization root state that this root reads the cross-root contract from."
  type        = string
  default     = "aws-organization"
}

# -----------------------------------------------------------------------------
# Provider region
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region the shared services are deployed in and the region the default provider assumes the shared-services-account role in."
  type        = string
  default     = "eu-west-2"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[1-9][0-9]?$", var.aws_region))
    error_message = "aws_region must be a valid AWS region name, e.g. eu-west-2."
  }
}

# -----------------------------------------------------------------------------
# ACM Private CA
# -----------------------------------------------------------------------------

variable "enable_private_ca" {
  description = "Whether to create the org-shared ACM Private CA. COST TOGGLE: ACM PCA bills a fixed monthly charge per CA from creation. Off by default."
  type        = bool
  default     = false
}

variable "ca_common_name" {
  description = "Common name (CN) placed in the CA certificate subject."
  type        = string
  default     = "org-internal-ca"
}

# -----------------------------------------------------------------------------
# Secrets Manager baseline
# -----------------------------------------------------------------------------

variable "enable_secrets_baseline" {
  description = "Whether to create the org Secrets Manager baseline (org-scoped secrets + optional rotation). Off by default."
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
  description = "ARN or ID of a customer-managed KMS key used to encrypt all baseline secrets. When empty, secrets use the account default aws/secretsmanager managed key."
  type        = string
  default     = ""
}
