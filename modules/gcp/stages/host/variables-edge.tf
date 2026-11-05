# Host stage (edge and ingress) inputs. Part of modules/gcp/stages/host.

# =============================================================================
# CLOUD ARMOR (WAF) CONFIGURATION
# =============================================================================

variable "enable_cloud_armor" {
  description = "Enable Cloud Armor WAF security policy"
  type        = bool
  default     = true
}

variable "enable_owasp_rules" {
  description = "Enable OWASP Top 10 WAF rules"
  type        = bool
  default     = true
}

variable "enable_adaptive_protection" {
  description = "Enable Cloud Armor adaptive protection (DDoS)"
  type        = bool
  default     = true
}

variable "enable_log4j_protection" {
  description = "Enable the Cloud Armor managed rule that blocks Log4Shell (CVE-2021-44228) exploit payloads. Requires enable_cloud_armor = true."
  type        = bool
  default     = true
}

variable "owasp_sensitivity" {
  description = "OWASP rule sensitivity level (1–4). Lower values apply stricter rules with more false positives; higher values are more permissive."
  type        = number
  default     = 2
  validation {
    condition     = contains([1, 2, 3, 4], var.owasp_sensitivity)
    error_message = "owasp_sensitivity must be 1, 2, 3, or 4."
  }
}

variable "cloud_armor_custom_rules" {
  description = <<-EOT
    Custom Cloud Armor rules passed through to the cloud_armor child module.

    Two mutually-exclusive match types are supported per rule:

    **IP-based (versioned_expr):**
      match_conditions = {
        versioned_expr = "SRC_IPS_V1"
        config         = { src_ip_ranges = ["10.0.0.0/8"] }
      }

    **CEL expression (expr):**
      match_conditions = {
        expr = "request.headers['user-agent'].lower().contains('scrapy')"
      }

    Exactly one of `versioned_expr` or `expr` must be set. Providing both or
    neither is rejected at plan time by the cloud_armor module.
  EOT
  type = map(object({
    action      = string
    priority    = number
    description = optional(string)
    match_conditions = object({
      # IP-based match. Set versioned_expr AND config, or set expr — never both.
      versioned_expr = optional(string)
      config = optional(object({
        src_ip_ranges = list(string)
      }))
      # CEL expression match. Mutually exclusive with versioned_expr + config.
      expr = optional(string)
    })
    rate_limit_options = optional(object({
      threshold_count     = number
      interval_sec        = number
      conform_action      = optional(string)
      exceed_action       = optional(string)
      enforce_on_key      = optional(string)
      enforce_on_key_type = optional(string)
    }))
  }))
  default = {}
}

# =============================================================================
# CDN CONFIGURATION
# =============================================================================

variable "enable_cdn" {
  description = "Enable Cloud CDN with Global Load Balancer"
  type        = bool
  default     = false
}

variable "cdn_domains" {
  description = "Domains for managed SSL certificate"
  type        = list(string)
  default     = []
}

variable "cdn_enable_http_redirect" {
  description = "Enable HTTP to HTTPS redirect"
  type        = bool
  default     = true
}

variable "cdn_backend_groups" {
  description = "Backend groups for the CDN load balancer"
  type = list(object({
    group           = string
    balancing_mode  = optional(string)
    capacity_scaler = optional(number)
    description     = optional(string)
  }))
  default = []
}

variable "cdn_policy" {
  description = "CDN caching policy configuration"
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

# =============================================================================
# API GATEWAY CONFIGURATION
# =============================================================================

variable "enable_api_gateway" {
  description = "Enable API Gateway"
  type        = bool
  default     = false
}

variable "api_gateway_display_name" {
  description = "Display name for the API Gateway"
  type        = string
  default     = "API Gateway"
}

variable "api_gateway_service_account" {
  description = "Service account email for the API Gateway backend service (format: name@project.iam.gserviceaccount.com). Required when enable_api_gateway is true."
  type        = string
  default     = ""

  validation {
    condition = !var.enable_api_gateway || (
      var.api_gateway_service_account != "" &&
      can(regex("^[a-z][a-z0-9-]*@[a-z0-9-]+\\.iam\\.gserviceaccount\\.com$", var.api_gateway_service_account))
    )
    error_message = "api_gateway_service_account must be a valid service account email (name@project.iam.gserviceaccount.com) when enable_api_gateway is true."
  }
}

variable "api_gateway_managed_services" {
  description = "Map of managed service IDs for auto-generated OpenAPI spec"
  type        = map(string)
  default     = {}
}

variable "api_gateway_openapi_spec" {
  description = "Custom OpenAPI specification (if not using managed_service_ids)"
  type        = string
  default     = ""
}

# =============================================================================
# INTERNAL LOAD BALANCER CONFIGURATION
# =============================================================================

variable "internal_load_balancers" {
  description = "Map of internal HTTP(S) load balancers to create"
  type = map(object({
    region     = string
    subnet     = string
    is_l7      = optional(bool, true)
    port_range = optional(string, "80")

    backends = list(object({
      group           = string
      balancing_mode  = optional(string, "UTILIZATION")
      capacity_scaler = optional(number, 1.0)
      max_utilization = optional(number, 0.8)
    }))

    # Health check
    health_check_type         = optional(string, "HTTP")
    health_check_port         = optional(number, 80)
    health_check_request_path = optional(string, "/health")

    # Optional settings
    allow_global_access = optional(bool, false)
    enable_ssl          = optional(bool, false)
    ssl_certificates    = optional(list(string), [])
    session_affinity    = optional(string, "NONE")
    enable_logging      = optional(bool, true)

    # Firewall
    create_firewall_rule     = optional(bool, true)
    proxy_only_subnet_ranges = optional(list(string), [])
    backend_target_tags      = optional(list(string), [])
    backend_port             = optional(number, 80)

    labels = optional(map(string), {})
  }))
  default = {}
}
