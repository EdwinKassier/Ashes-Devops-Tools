variable "project_id" {
  description = "The ID of the project where the Cloud Run services will be created"
  type        = string
}

variable "region" {
  description = "The region where the Cloud Run services will be deployed"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "The environment (e.g., 'development', 'staging', 'production')"
  type        = string
  default     = "production"
}

variable "ingress_policy" {
  description = "The ingress policy for the Cloud Run services"
  type        = string
  default     = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
}

variable "service_account_email" {
  description = "The email of the service account to run the Cloud Run services as"
  type        = string
  default     = ""
}

variable "vpc_connector" {
  description = "The VPC connector to use for the Cloud Run services"
  type        = string
  default     = ""
}

variable "cpu" {
  description = "CPU allocation for each container"
  type        = string
  default     = "1000m"
}

variable "memory" {
  description = "Memory allocation for each container"
  type        = string
  default     = "512Mi"
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
}

variable "labels" {
  description = "A map of labels to apply to the Cloud Run services"
  type        = map(string)
  default     = {}
}

variable "additional_invokers" {
  description = "A map of service names to lists of IAM members who should be able to invoke the services"
  type        = map(string)
  default     = {}
}

variable "service_ports" {
  description = "A map of service names to their container ports"
  type        = map(number)
  default = {
    "ashes-flask"  = 8080
    "ashes-django" = 8000
    "ashes-fastapi" = 8000
    "ashes-express" = 8080
    "ashes-hermes"  = 8080
  }
}