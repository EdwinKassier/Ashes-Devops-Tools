variable "region" {
  description = "AWS region of the disposable sandbox account the suite applies into."
  type        = string
  default     = "eu-west-2"
}

variable "run_id" {
  description = "Unique run identifier (github.run_id in CI). Stamped on every resource as the e2e-run-id tag and used in every resource name."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-z]{1,20}$", var.run_id))
    error_message = "run_id must be 1-20 lowercase letters or digits (it is used in S3 bucket names and tag values)."
  }
}

variable "run_attempt" {
  description = "Re-run attempt number (github.run_attempt in CI). Part of resource names so a re-run never collides with a KMS alias or bucket from an earlier attempt."
  type        = string
  default     = "1"

  validation {
    condition     = can(regex("^[0-9]{1,3}$", var.run_attempt))
    error_message = "run_attempt must be a 1-3 digit number."
  }
}

variable "org_id" {
  description = "Organization ID written into the log-delivery aws:SourceOrgID conditions of the key and bucket policies. The suite never delivers org logs, so a placeholder is fine for a standalone sandbox account."
  type        = string
  default     = "o-e2esandbox00"
}
