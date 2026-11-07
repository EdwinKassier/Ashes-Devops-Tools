/**
 * Copyright 2026 Ashes
 *
 * Cloud Run Job (v2) Module - Variables
 */

# -----------------------------------------------------------------------------
# REQUIRED
# -----------------------------------------------------------------------------

variable "project_id" {
  description = "The GCP project ID where the Cloud Run job is created."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be 6-30 characters, start with a lowercase letter, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "location" {
  description = "The GCP region for the Cloud Run job (e.g. europe-west1)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.location))
    error_message = "location must be a valid GCP region (e.g. \"europe-west1\")."
  }
}

variable "name" {
  description = "Name of the Cloud Run job."
  type        = string

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$", var.name))
    error_message = "name must start with a lowercase letter, contain only lowercase letters, digits and hyphens, and be at most 63 characters."
  }
}

variable "image" {
  description = "Fully qualified container image the job runs at creation (e.g. europe-west1-docker.pkg.dev/project/repo/job:tag). Later image changes are owned by the delivery pipeline and ignored by Terraform."
  type        = string

  validation {
    condition     = length(trimspace(var.image)) > 0
    error_message = "image must be a non-empty container image reference."
  }
}

variable "service_account_email" {
  description = "Email of the dedicated runtime service account the job's tasks run as. Required: never run on the default compute SA."
  type        = string

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.iam\\.gserviceaccount\\.com$", var.service_account_email))
    error_message = "service_account_email must be a valid IAM service account email (…@….iam.gserviceaccount.com)."
  }
}

# -----------------------------------------------------------------------------
# EXECUTION
# -----------------------------------------------------------------------------

variable "task_count" {
  description = "Number of tasks each execution runs."
  type        = number
  default     = 1

  validation {
    condition     = var.task_count >= 1 && var.task_count <= 10000 && floor(var.task_count) == var.task_count
    error_message = "task_count must be a whole number between 1 and 10000."
  }
}

variable "parallelism" {
  description = "Maximum number of tasks running at once. Null lets Cloud Run run as many as possible."
  type        = number
  default     = null

  validation {
    condition     = var.parallelism == null || (try(var.parallelism >= 1, false) && try(floor(var.parallelism) == var.parallelism, false))
    error_message = "parallelism must be null or a whole number of at least 1."
  }
}

variable "max_retries" {
  description = "Times a failed task is retried before the execution fails."
  type        = number
  default     = 3

  validation {
    condition     = var.max_retries >= 0 && var.max_retries <= 10 && floor(var.max_retries) == var.max_retries
    error_message = "max_retries must be a whole number between 0 and 10."
  }
}

variable "timeout" {
  description = "Maximum duration of one task attempt, as a seconds string (e.g. \"600s\")."
  type        = string
  default     = "600s"

  validation {
    condition     = can(regex("^[0-9]+(\\.[0-9]+)?s$", var.timeout))
    error_message = "timeout must be a seconds duration string such as \"600s\"."
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
    to a secret version via value_source.secret_key_ref; secret material is NEVER
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
  description = "CPU limit per task container (e.g. \"1000m\", \"1\", \"2\")."
  type        = string
  default     = "1000m"
}

variable "memory" {
  description = "Memory limit per task container (e.g. \"512Mi\", \"1Gi\")."
  type        = string
  default     = "512Mi"
}

# -----------------------------------------------------------------------------
# NETWORKING
# -----------------------------------------------------------------------------

variable "vpc_access" {
  description = <<-EOT
    Optional VPC egress configuration. Supply a connector for connector-based egress,
    or a network_interfaces object for Direct VPC egress (not both). When null (the
    default) the job has no VPC egress.
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
  description = "Labels applied to the Cloud Run job."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# DELETION PROTECTION
# -----------------------------------------------------------------------------

variable "enable_deletion_protection" {
  description = "Prevent accidental destruction of the Cloud Run job. Maps directly to the resource's deletion_protection attribute. Defaults to true."
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
    runs an image that violates the policy (audited); leave null normally.
  EOT
  type = object({
    policy                   = optional(string)
    breakglass_justification = optional(string)
  })
  default = null
}
