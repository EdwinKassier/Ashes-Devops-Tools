variable "project_id" {
  description = "Dedicated, disposable GCP sandbox project the suite applies into. Never point this at a landing-zone project."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project ID (6-30 chars, lowercase letters, digits, hyphens)."
  }
}

variable "region" {
  description = "Region for every regional resource (KMS keyring, buckets, subnet, secret replica)."
  type        = string
  default     = "europe-west2"
}

variable "run_id" {
  description = "Unique run identifier (github.run_id in CI). Stamped on every resource as the e2e-run-id label and used in every resource name."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-z]{1,20}$", var.run_id))
    error_message = "run_id must be 1-20 lowercase letters or digits (it is used in resource names and label values)."
  }
}

variable "run_attempt" {
  description = "Re-run attempt number (github.run_attempt in CI). Part of resource names so a re-run never collides with an undeletable keyring from an earlier attempt."
  type        = string
  default     = "1"

  validation {
    condition     = can(regex("^[0-9]{1,3}$", var.run_attempt))
    error_message = "run_attempt must be a 1-3 digit number."
  }
}
