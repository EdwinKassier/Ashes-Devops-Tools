# Required variables — no defaults, callers must supply these.

variable "name" {
  description = "The name of the SSM parameter (fully-qualified path, e.g. /app/config/key)"
  type        = string

  # Note: the RE2 engine Terraform uses caps interval repeat counts at 1000,
  # so the upper bound is 1000 (not 1024) — well above any real SSM name length.
  validation {
    condition     = can(regex("^[a-zA-Z0-9_./-]{1,1000}$", var.name))
    error_message = "name must be 1-1000 characters and contain only letters, digits, and the characters _ . / -"
  }
}

# Optional variables — document sensible defaults and constraints.

variable "value" {
  description = "The value stored in the SSM parameter"
  type        = string
  default     = "placeholder"
}
