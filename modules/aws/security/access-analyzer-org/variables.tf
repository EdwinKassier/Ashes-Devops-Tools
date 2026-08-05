variable "external_analyzer_name" {
  description = "Name of the organization-scoped external-access analyzer."
  type        = string
  default     = "org-external-access"

  validation {
    condition     = length(trimspace(var.external_analyzer_name)) > 0
    error_message = "external_analyzer_name must be a non-empty string."
  }
}

variable "unused_analyzer_name" {
  description = "Name of the organization-scoped unused-access analyzer."
  type        = string
  default     = "org-unused-access"

  validation {
    condition     = length(trimspace(var.unused_analyzer_name)) > 0
    error_message = "unused_analyzer_name must be a non-empty string."
  }
}

variable "unused_access_age" {
  description = "Number of days without use after which IAM access is flagged as unused by the unused-access analyzer."
  type        = number
  default     = 90

  validation {
    condition     = var.unused_access_age >= 1
    error_message = "unused_access_age must be at least 1 day."
  }
}
