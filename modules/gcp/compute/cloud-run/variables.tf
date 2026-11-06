/**
 * Copyright 2023 Ashes
 *
 * Cloud Run (v2) Module - Variables
 */

# -----------------------------------------------------------------------------
# REQUIRED
# -----------------------------------------------------------------------------

variable "project_id" {
  description = "The GCP project ID where the Cloud Run service is created."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be 6-30 characters, start with a lowercase letter, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "location" {
  description = "The GCP region for the Cloud Run service (e.g. europe-west1)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.location))
    error_message = "location must be a valid GCP region (e.g. \"europe-west1\")."
  }
}

variable "name" {
  description = "Name of the Cloud Run service."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", var.name))
    error_message = "name must start with a lowercase letter, contain only lowercase letters, digits and hyphens, and be at most 63 characters."
  }
}

variable "image" {
  description = "Fully qualified container image to deploy at creation (e.g. europe-west1-docker.pkg.dev/project/repo/app:tag). Later image changes are owned by the delivery pipeline and ignored by Terraform."
  type        = string

  validation {
    condition     = length(trimspace(var.image)) > 0
    error_message = "image must be a non-empty container image reference."
  }
}

variable "service_account_email" {
  description = "Email of the dedicated runtime service account the service runs as. Required — never run on the default compute SA."
  type        = string

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.iam\\.gserviceaccount\\.com$", var.service_account_email))
    error_message = "service_account_email must be a valid IAM service account email (…@….iam.gserviceaccount.com)."
  }
}

# -----------------------------------------------------------------------------
# CONTAINER CONFIG
# -----------------------------------------------------------------------------

variable "env_vars" {
  description = "Plain (non-secret) environment variables injected into the container as name => value."
  type        = map(string)
  default     = {}
}

variable "secret_env_vars" {
  description = <<-EOT
    Environment variables sourced from Secret Manager. Each entry wires an env var
    to a secret version via value_source.secret_key_ref — secret material is NEVER
    passed as plaintext here.
      name    = env var name exposed to the container
      secret  = Secret Manager secret id (short id or projects/<p>/secrets/<s>)
      version = secret version ("latest" or a numeric version)
  EOT
  type = list(object({
    name    = string
    secret  = string
    version = optional(string, "latest")
  }))
  default = []
}

variable "cpu" {
  description = "CPU limit per container instance (e.g. \"1000m\", \"1\", \"2\")."
  type        = string
  default     = "1000m"
}

variable "memory" {
  description = "Memory limit per container instance (e.g. \"512Mi\", \"1Gi\")."
  type        = string
  default     = "512Mi"
}

variable "concurrency" {
  description = "Maximum number of concurrent requests per instance (max_instance_request_concurrency)."
  type        = number
  default     = 80

  validation {
    condition     = var.concurrency >= 1 && var.concurrency <= 1000
    error_message = "concurrency must be between 1 and 1000."
  }
}

variable "timeout" {
  description = "Maximum request duration, as a duration string (e.g. \"300s\")."
  type        = string
  default     = "300s"
}

# -----------------------------------------------------------------------------
# SCALING
# -----------------------------------------------------------------------------

variable "min_instance_count" {
  description = "Minimum number of instances (0 allows scale-to-zero)."
  type        = number
  default     = 0

  validation {
    condition     = var.min_instance_count >= 0
    error_message = "min_instance_count must be zero or greater."
  }
}

variable "max_instance_count" {
  description = "Maximum number of instances."
  type        = number
  default     = 100

  validation {
    condition     = var.max_instance_count >= 1 && var.max_instance_count >= var.min_instance_count
    error_message = "max_instance_count must be at least 1 and not less than min_instance_count."
  }
}

# -----------------------------------------------------------------------------
# NETWORKING
# -----------------------------------------------------------------------------

variable "ingress" {
  description = <<-EOT
    Ingress traffic policy. Defaults to INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER so the
    service is reachable only via an internal HTTP(S) load balancer (not the public
    internet). Set to INGRESS_TRAFFIC_ALL only for deliberately public services.
  EOT
  type        = string
  default     = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  validation {
    condition = contains([
      "INGRESS_TRAFFIC_ALL",
      "INGRESS_TRAFFIC_INTERNAL_ONLY",
      "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER",
    ], var.ingress)
    error_message = "ingress must be one of INGRESS_TRAFFIC_ALL, INGRESS_TRAFFIC_INTERNAL_ONLY, or INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER."
  }
}

variable "vpc_access" {
  description = <<-EOT
    Optional VPC egress configuration. Supply a connector for connector-based egress,
    or a network_interfaces object for Direct VPC egress (not both). When null (the
    default) the service has no VPC egress.
      connector = fully qualified VPC Access connector id (connector mode)
      egress    = ALL_TRAFFIC or PRIVATE_RANGES_ONLY
      network_interfaces = { network, subnetwork, tags } for Direct VPC egress
  EOT
  type = object({
    connector = optional(string)
    egress    = optional(string, "PRIVATE_RANGES_ONLY")
    network_interfaces = optional(object({
      network    = optional(string)
      subnetwork = optional(string)
      tags       = optional(list(string))
    }))
  })
  default = null

  validation {
    condition     = var.vpc_access == null || contains(["ALL_TRAFFIC", "PRIVATE_RANGES_ONLY"], try(var.vpc_access.egress, "PRIVATE_RANGES_ONLY"))
    error_message = "vpc_access.egress must be either ALL_TRAFFIC or PRIVATE_RANGES_ONLY."
  }
}

variable "labels" {
  description = "Labels applied to the Cloud Run service."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# ACCESS
# -----------------------------------------------------------------------------

variable "enable_unauthenticated" {
  description = <<-EOT
    When true, grants roles/run.invoker to allUsers, making the service publicly
    invokable without authentication. Defaults to false — the service is private and
    only callable by principals with an explicit invoker binding.
  EOT
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# DELETION PROTECTION
# -----------------------------------------------------------------------------

variable "enable_deletion_protection" {
  description = <<-EOT
    Prevent accidental destruction of the Cloud Run service. Maps directly to the
    resource's deletion_protection attribute. Defaults to true; set to false to allow
    `terraform destroy` to remove the service.
  EOT
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# SUPPLY CHAIN
# -----------------------------------------------------------------------------

variable "binary_authorization" {
  description = <<-EOT
    Optional Binary Authorization enforcement. Null (default) disables it. Set
    `{}` to enforce the project's default Binary Authorization policy, or set
    `policy` to the full name of a platform policy
    (projects/<p>/platforms/cloudRun/policies/<name>). `breakglass_justification`
    deploys an image that violates the policy (audited) — leave null normally.
  EOT
  type = object({
    policy                   = optional(string)
    breakglass_justification = optional(string)
  })
  default = null
}
