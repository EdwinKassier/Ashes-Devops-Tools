# -----------------------------------------------------------------------------
# Placement
# -----------------------------------------------------------------------------

variable "project_id" {
  description = "Project ID where the CA pool and certificate authority will be created (6-30 characters, lowercase alphanumeric and hyphens)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be 6-30 characters, start with a lowercase letter, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "location" {
  description = "GCP region for the CA pool and certificate authority (e.g. europe-west1)."
  type        = string
  default     = "europe-west1"
}

# -----------------------------------------------------------------------------
# CA pool
# -----------------------------------------------------------------------------

variable "ca_pool_name" {
  description = "Name of the CA pool (1-63 alphanumeric characters, hyphens, and underscores)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,63}$", var.ca_pool_name))
    error_message = "ca_pool_name must be 1-63 characters containing only alphanumeric characters, hyphens, and underscores."
  }
}

variable "tier" {
  description = "CA pool tier. ENTERPRISE supports per-certificate revocation and long-lived CAs; DEVOPS is cheaper but drops per-certificate features. Defaults to ENTERPRISE."
  type        = string
  default     = "ENTERPRISE"

  validation {
    condition     = contains(["ENTERPRISE", "DEVOPS"], var.tier)
    error_message = "tier must be either ENTERPRISE or DEVOPS."
  }
}

# -----------------------------------------------------------------------------
# Certificate authority
# -----------------------------------------------------------------------------

variable "enable_ca" {
  description = "When true (default) the certificate authority is created and enabled inside the pool. When false only the pool is created, staging the CA for a later apply. CAS bills per active CA, so this gate lets the pool exist without incurring CA charges."
  type        = bool
  default     = true
}

variable "name" {
  description = "Certificate authority ID (1-63 alphanumeric characters, hyphens, and underscores)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,63}$", var.name))
    error_message = "name must be 1-63 characters containing only alphanumeric characters, hyphens, and underscores."
  }
}

variable "ca_type" {
  description = "Type of certificate authority. ROOT anchors the hierarchy (self-signed); SUBORDINATE is signed by a parent CA."
  type        = string
  default     = "ROOT"

  validation {
    condition     = contains(["ROOT", "SUBORDINATE"], var.ca_type)
    error_message = "ca_type must be either ROOT or SUBORDINATE."
  }
}

variable "subject" {
  description = "Subject placed in the CA certificate: organization (O) and common name (CN)."
  type = object({
    organization = string
    common_name  = string
  })
  default = {
    organization = "Example Org"
    common_name  = "org-internal-ca"
  }
}

variable "key_algorithm" {
  description = "Algorithm used to generate the CA's key pair (e.g. RSA_PKCS1_4096_SHA256, EC_P256_SHA256, EC_P384_SHA384)."
  type        = string
  default     = "RSA_PKCS1_4096_SHA256"
}

variable "lifetime" {
  description = "Lifetime of the CA certificate as a duration in seconds (e.g. '315360000s' for 10 years). Defaults to 10 years, appropriate for a long-lived root."
  type        = string
  default     = "315360000s"
}

# -----------------------------------------------------------------------------
# Lifecycle safety
# -----------------------------------------------------------------------------

variable "deletion_protection" {
  description = "When true (default) Terraform refuses to destroy the certificate authority, guarding against accidental teardown of the org's trust anchor."
  type        = bool
  default     = true
}

variable "ignore_active_certificates_on_deletion" {
  description = "When true, the CA can be deleted even while it has active issued certificates. Defaults to false — the safe setting that blocks deletion until certificates are dealt with."
  type        = bool
  default     = false
}

variable "skip_grace_period" {
  description = "When true, deletion skips the CAS grace period and the CA is scheduled for permanent destruction immediately. Defaults to false so the recovery grace period is honoured."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels applied to the CA pool and certificate authority."
  type        = map(string)
  default     = {}
}
