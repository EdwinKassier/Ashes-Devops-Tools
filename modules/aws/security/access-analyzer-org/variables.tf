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

variable "home_region" {
  description = "Region of the provider this module runs with; the unkeyed external/internal analyzers live here. Required when regions is non-empty."
  type        = string
  default     = ""
  nullable    = false
}

variable "regions" {
  description = "Enabled regions to create the external (and, if enabled, internal) analyzers in. Every region other than home_region gets an analyzer through the resource-level region argument. Empty (default) creates only the home-region analyzers."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = length(var.regions) == 0 || var.home_region != ""
    error_message = "home_region must be set when regions is non-empty, so the home-region analyzer is not duplicated."
  }

  validation {
    condition     = alltrue([for r in var.regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]{1,2}$", r))])
    error_message = "regions entries must be valid AWS region ids (e.g. eu-west-2)."
  }
}

variable "enable_internal_access_analyzer" {
  description = "Create the ORGANIZATION_INTERNAL_ACCESS analyzer in the home region and every entry of regions."
  type        = bool
  default     = false
  nullable    = false
}

variable "internal_analyzer_name" {
  description = "Name of the organization-scoped internal-access analyzer."
  type        = string
  default     = "org-internal-access"

  validation {
    condition     = length(trimspace(var.internal_analyzer_name)) > 0
    error_message = "internal_analyzer_name must be a non-empty string."
  }
}

variable "internal_access_resource_types" {
  description = "Resource types (e.g. AWS::S3::Bucket) the internal-access analyzer monitors. Empty monitors all supported types."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "tags" {
  description = "Tags applied to every taggable resource this module creates (merged after provider default_tags; resource-specific tags such as Name win)."
  type        = map(string)
  default     = {}
  nullable    = false
}
