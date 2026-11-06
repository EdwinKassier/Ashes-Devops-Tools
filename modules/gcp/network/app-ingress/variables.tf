variable "project_id" {
  description = "GCP project ID that hosts the load balancer, certificate, and backend."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project ID (6-30 chars, lowercase letters, digits, hyphens)."
  }
}

variable "region" {
  description = "Region of the Cloud Run service the serverless NEG targets, e.g. europe-west1."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "region must be a valid GCP region name, e.g. europe-west1."
  }
}

variable "name" {
  description = "Base name for the load balancer resources. Each resource appends a suffix (-ip, -neg, -backend, -cert, ...)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([a-z0-9-]{0,40}[a-z0-9])?$", var.name))
    error_message = "name must start with a letter, be 1-42 chars, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "domains" {
  description = "Fully qualified domains the managed certificate covers and the load balancer serves, e.g. [\"api.example.com\"]. At least one is required; Google provisions one managed cert covering all of them."
  type        = list(string)

  validation {
    condition     = length(var.domains) > 0
    error_message = "At least one domain is required for the managed certificate."
  }

  validation {
    condition     = alltrue([for d in var.domains : can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", d))])
    error_message = "Every domain must be a fully qualified domain name, e.g. api.example.com."
  }
}

variable "cloud_run_service_name" {
  description = "Name of the Cloud Run service in var.region the serverless NEG routes to (e.g. the name output of modules/gcp/compute/cloud-run)."
  type        = string

  validation {
    condition     = length(trimspace(var.cloud_run_service_name)) > 0
    error_message = "cloud_run_service_name must be a non-empty Cloud Run service name."
  }
}

variable "security_policy_id" {
  description = "Optional Cloud Armor security policy ID (self_link) to attach to the backend service. Null leaves the backend without an edge WAF, so set this for any internet-facing service that needs rate limiting or OWASP rules."
  type        = string
  default     = null
}

variable "ssl_policy_id" {
  description = "Optional SSL policy ID (self_link) for the HTTPS proxy. Null uses Google's default negotiation; set a MODERN or RESTRICTED policy to pin a minimum TLS version."
  type        = string
  default     = null
}

variable "enable_cdn" {
  description = "Enable Cloud CDN on the backend service. Default false; turn on for cacheable public content."
  type        = bool
  default     = false
}

variable "dns_managed_zone" {
  description = "Optional Cloud DNS managed-zone name in var.project_id. When set, the module creates an A record per domain pointing at the load balancer IP. Null leaves DNS to the operator (the module still outputs the IP to point records at)."
  type        = string
  default     = null
}

variable "dns_ttl" {
  description = "TTL in seconds for the DNS A records, used only when dns_managed_zone is set."
  type        = number
  default     = 300

  validation {
    condition     = var.dns_ttl >= 0 && var.dns_ttl <= 86400
    error_message = "dns_ttl must be between 0 and 86400 seconds."
  }
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
