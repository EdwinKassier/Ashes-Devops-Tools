variable "project_id" {
  description = "The ID of the project where the Cloud Run services will be created"
  type        = string

  validation {
    condition     = length(var.project_id) >= 6 && length(var.project_id) <= 30
    error_message = "Project ID must be between 6 and 30 characters"
  }

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.project_id))
    error_message = "Project ID must start with letter, contain only lowercase letters, numbers, and hyphens"
  }
}

variable "region" {
  description = "The region where the Cloud Run services will be deployed"
  type        = string
  default     = "us-central1"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid GCP region format (e.g., us-central1)"
  }
}

variable "environment" {
  description = "The environment (e.g., 'development', 'staging', 'production', 'uat')"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["development", "staging", "production", "uat"], var.environment)
    error_message = "Environment must be one of: development, staging, production, uat"
  }
}

variable "ingress_policy" {
  description = "The ingress policy for the Cloud Run services"
  type        = string
  default     = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  validation {
    condition = contains([
      "INGRESS_TRAFFIC_ALL",
      "INGRESS_TRAFFIC_INTERNAL_ONLY",
      "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
    ], var.ingress_policy)
    error_message = "Ingress policy must be one of: INGRESS_TRAFFIC_ALL, INGRESS_TRAFFIC_INTERNAL_ONLY, INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  }
}

variable "service_account_email" {
  description = "The email of the service account to run the Cloud Run services as"
  type        = string
  default     = ""
}

variable "vpc_connector" {
  description = "The VPC connector to use for the Cloud Run services (format: projects/PROJECT/locations/REGION/connectors/CONNECTOR)"
  type        = string
  default     = ""
}

variable "vpc_egress_setting" {
  description = "VPC egress setting - controls which traffic routes through VPC"
  type        = string
  default     = "PRIVATE_RANGES_ONLY"

  validation {
    condition     = contains(["ALL_TRAFFIC", "PRIVATE_RANGES_ONLY"], var.vpc_egress_setting)
    error_message = "VPC egress setting must be either ALL_TRAFFIC or PRIVATE_RANGES_ONLY"
  }
}

variable "cpu" {
  description = "CPU allocation for each container (e.g., '1000m' = 1 CPU, '2000m' = 2 CPUs)"
  type        = string
  default     = "1000m"

  validation {
    condition     = can(regex("^[0-9]+m$", var.cpu))
    error_message = "CPU must be specified in millicores (e.g., 1000m)"
  }
}

variable "memory" {
  description = "Memory allocation for each container"
  type        = string
  default     = "512Mi"

  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi)$", var.memory))
    error_message = "Memory must be specified in Mi or Gi (e.g., 512Mi, 2Gi)"
  }
}

variable "environment_variables" {
  description = "A map of environment variables to pass to the containers"
  type        = map(string)
  default     = {}
}

variable "liveness_path" {
  description = "The path for the liveness probe"
  type        = string
  default     = "/healthz"
}

variable "readiness_path" {
  description = "The path for the readiness probe"
  type        = string
  default     = "/ready"
}

variable "enable_session_affinity" {
  description = "Whether to enable session affinity"
  type        = bool
  default     = false
}

variable "max_concurrent_requests" {
  description = "Maximum number of concurrent requests each container instance can handle"
  type        = number
  default     = 80

  validation {
    condition     = var.max_concurrent_requests > 0 && var.max_concurrent_requests <= 1000
    error_message = "Max concurrent requests must be between 1 and 1000"
  }
}

variable "labels" {
  description = "A map of labels to apply to the Cloud Run services"
  type        = map(string)
  default     = {}
}

variable "additional_invokers" {
  description = "A map of service names to IAM members who should be able to invoke the services"
  type        = map(string)
  default     = {}
}
