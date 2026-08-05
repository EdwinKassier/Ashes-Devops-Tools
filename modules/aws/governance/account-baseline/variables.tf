# -----------------------------------------------------------------------------
# Region scope
# -----------------------------------------------------------------------------

variable "aws_enabled_regions" {
  description = "Regions in which to enforce default EBS encryption (and, if set, the default EBS KMS key). Defaults to the single home Region."
  type        = list(string)
  default     = ["eu-west-2"]

  validation {
    condition     = length(var.aws_enabled_regions) > 0
    error_message = "aws_enabled_regions must contain at least one Region."
  }
}

variable "kms_key_arn" {
  description = "ARN of the CMK to set as the account default EBS encryption key per Region. Empty string leaves default EBS encryption on the AWS-managed key."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# IAM account password policy
# -----------------------------------------------------------------------------

variable "password_min_length" {
  description = "Minimum length for IAM user passwords. CIS requires at least 14."
  type        = number
  default     = 14

  validation {
    condition     = var.password_min_length >= 14
    error_message = "password_min_length must be at least 14 (CIS AWS Foundations benchmark)."
  }
}

variable "password_max_age" {
  description = "Maximum age in days before an IAM user password must be rotated."
  type        = number
  default     = 90
}

variable "password_reuse_prevention" {
  description = "Number of previous IAM user passwords that cannot be reused."
  type        = number
  default     = 24
}
