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
  description = "List of domains for the managed SSL certificate. If empty, no SSL cert is created."
  type        = list(string)
  default     = []
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
