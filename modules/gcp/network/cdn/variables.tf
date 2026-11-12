/**
 * Copyright 2023 Ashes
 *
 * CDN Module - Variables
 */

variable "project_id" {
  description = "The project ID where the CDN resources will be created"
  type        = string
}

variable "lb_name" {
  description = "Name for the load balancer resources"
  type        = string
}

variable "domains" {
  description = "List of domains for the managed SSL certificate. At least one is required (the module always creates an HTTPS proxy backed by a managed SSL certificate)."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.domains) > 0
    error_message = "At least one domain is required (a managed SSL certificate and HTTPS proxy are always created)."
  }
}

variable "backend_groups" {
  description = "List of Backend references (Instance Groups or NEGs) with configuration"
  type = list(object({
    group           = string
    balancing_mode  = optional(string)
    capacity_scaler = optional(number)
    description     = optional(string)
  }))
  default = []
}

variable "enable_cdn" {
  description = "Enable Cloud CDN for this Global Load Balancer"
  type        = bool
  default     = true
}

variable "cdn_policy" {
  description = "Cloud CDN configuration policy"
  type = object({
    cache_mode                   = optional(string, "CACHE_ALL_STATIC")
    client_ttl                   = optional(number, 3600)
    default_ttl                  = optional(number, 3600)
    max_ttl                      = optional(number, 86400)
    negative_caching             = optional(bool, true)
    signed_url_cache_max_age_sec = optional(number, 0)
  })
  default = {}

  validation {
    condition     = contains(["USE_ORIGIN_HEADERS", "FORCE_CACHE_ALL", "CACHE_ALL_STATIC"], var.cdn_policy.cache_mode)
    error_message = "cdn_policy.cache_mode must be USE_ORIGIN_HEADERS, FORCE_CACHE_ALL, or CACHE_ALL_STATIC."
  }
}

variable "security_policy" {
  description = "Self link of a Cloud Armor security policy to attach to the backend service"
  type        = string
  default     = null
}

variable "enable_http_redirect" {
  description = "Enable HTTP to HTTPS redirect (recommended for production)"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels applied to every labelable resource this module creates (merged with the provider default_labels; resource-specific labels win)."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for k, v in var.labels : can(regex("^[a-z][a-z0-9_-]{0,62}$", k)) && can(regex("^[a-z0-9_-]{0,63}$", v))
    ])
    error_message = "labels keys/values must be lowercase GCP label syntax (keys start with a letter, <= 63 chars)."
  }
}

variable "ssl_policy_id" {
  description = "Optional SSL policy ID (self_link) for the HTTPS proxy, used as is. Null creates a MODERN TLS 1.2 policy (min_tls_version, ssl_policy_profile)."
  type        = string
  default     = null
}

variable "min_tls_version" {
  description = "Minimum TLS version of the SSL policy this module creates when ssl_policy_id is null."
  type        = string
  default     = "TLS_1_2"

  validation {
    condition     = contains(["TLS_1_2", "TLS_1_3"], var.min_tls_version)
    error_message = "min_tls_version must be TLS_1_2 or TLS_1_3."
  }
}

variable "ssl_policy_profile" {
  description = "Profile of the created SSL policy: MODERN (default) or RESTRICTED (required for TLS_1_3)."
  type        = string
  default     = "MODERN"

  validation {
    condition     = contains(["MODERN", "RESTRICTED"], var.ssl_policy_profile) && (var.min_tls_version != "TLS_1_3" || var.ssl_policy_profile == "RESTRICTED")
    error_message = "ssl_policy_profile must be MODERN or RESTRICTED, and RESTRICTED when min_tls_version is TLS_1_3."
  }
}
