/**
 * Copyright 2023 Ashes
 *
 * Internal HTTP(S) Load Balancer Module - Variables
 */

variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "name" {
  description = "Base name for load balancer resources"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,62}$", var.name))
    error_message = "Name must start with a letter, contain only lowercase letters, numbers, and hyphens."
  }
}

variable "region" {
  description = "The region for the load balancer"
  type        = string
}

variable "network" {
  description = "The VPC network self_link or ID"
  type        = string
}

variable "subnet" {
  description = "The subnet self_link for the load balancer"
  type        = string
}

variable "is_l7" {
  description = "Whether to create an L7 (HTTP/S) load balancer (true) or L4 TCP (false)"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to the forwarding rule"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# IP Address Configuration
# -----------------------------------------------------------------------------

variable "create_static_ip" {
  description = "Whether to create a static internal IP address"
  type        = bool
  default     = true
}

variable "ip_address" {
  description = "Static IP address (if create_static_ip is false)"
  type        = string
  default     = null
}

variable "port_range" {
  description = "Port range for the forwarding rule (e.g., '80' or '8080-8090')"
  type        = string
  default     = "80"
}

variable "allow_global_access" {
  description = "Allow clients from any region to access the load balancer"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Health Check Configuration
# -----------------------------------------------------------------------------

variable "create_health_check" {
  description = "Whether to create a health check"
  type        = bool
  default     = true
}

variable "health_check_self_link" {
  description = "Existing health check self_link (if create_health_check is false)"
  type        = string
  default     = null
}

variable "health_check_type" {
  description = "Type of health check: HTTP, HTTPS, TCP, or GRPC"
  type        = string
  default     = "HTTP"

  validation {
    condition     = contains(["HTTP", "HTTPS", "TCP", "GRPC"], var.health_check_type)
    error_message = "Health check type must be HTTP, HTTPS, TCP, or GRPC."
  }
}

variable "health_check_port" {
  description = "Port for health checks"
  type        = number
  default     = 80
}

variable "health_check_request_path" {
  description = "Request path for HTTP/HTTPS health checks"
  type        = string
  default     = "/health"
}

variable "health_check_interval_sec" {
  description = "Health check interval in seconds"
  type        = number
  default     = 5
}

variable "health_check_timeout_sec" {
  description = "Health check timeout in seconds"
  type        = number
  default     = 5
}

variable "health_check_healthy_threshold" {
  description = "Number of successful checks before marking healthy"
  type        = number
  default     = 2
}

variable "health_check_unhealthy_threshold" {
  description = "Number of failed checks before marking unhealthy"
  type        = number
  default     = 2
}

variable "grpc_service_name" {
  description = "Service name for gRPC health checks"
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Backend Configuration
# -----------------------------------------------------------------------------

variable "backends" {
  description = "List of backend instance groups or NEGs"
  type = list(object({
    group           = string
    balancing_mode  = optional(string, "UTILIZATION")
    capacity_scaler = optional(number, 1.0)
    max_utilization = optional(number, 0.8)
    max_connections = optional(number)
    max_rate        = optional(number)
  }))
}

variable "backend_timeout_sec" {
  description = "Backend service timeout in seconds"
  type        = number
  default     = 30
}

variable "session_affinity" {
  description = "Session affinity: NONE, CLIENT_IP, or GENERATED_COOKIE"
  type        = string
  default     = "NONE"
}

variable "locality_lb_policy" {
  description = "Locality load balancing policy"
  type        = string
  default     = "ROUND_ROBIN"
}

variable "connection_draining_timeout_sec" {
  description = "Connection draining timeout in seconds"
  type        = number
  default     = 300
}

variable "backend_port" {
  description = "Backend service port (for firewall rules)"
  type        = number
  default     = 80
}

variable "backend_target_tags" {
  description = "Network tags for backend instances"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# URL Mapping (L7 only)
# -----------------------------------------------------------------------------

variable "host_rules" {
  description = "Host rules for URL mapping"
  type = list(object({
    hosts        = list(string)
    path_matcher = string
  }))
  default = []
}

variable "path_matchers" {
  description = "Path matchers for URL mapping"
  type = list(object({
    name            = string
    default_service = string
    path_rules = optional(list(object({
      paths   = list(string)
      service = string
    })))
  }))
  default = []
}

# -----------------------------------------------------------------------------
# SSL Configuration
# -----------------------------------------------------------------------------

variable "enable_ssl" {
  description = "Enable HTTPS for the load balancer"
  type        = bool
  default     = false
}

variable "ssl_certificates" {
  description = "List of SSL certificate self_links (for HTTPS)"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Logging & Firewall
# -----------------------------------------------------------------------------

variable "enable_logging" {
  description = "Enable access logging"
  type        = bool
  default     = true
}

variable "log_sample_rate" {
  description = "Sample rate for access logs (0.0 to 1.0)"
  type        = number
  default     = 1.0
}

variable "create_firewall_rule" {
  description = "Create firewall rule for proxy-only subnet"
  type        = bool
  default     = true
}

variable "proxy_only_subnet_ranges" {
  description = "CIDR ranges for proxy-only subnets"
  type        = list(string)
  default     = []
}

variable "firewall_priority" {
  description = "Priority for the proxy-only subnet firewall rule"
  type        = number
  default     = 1000
}
