# Required variables — no defaults, callers must supply these.

variable "project_id" {
  description = "The GCP project ID where resources will be created"
  type        = string
}

# Optional variables — document sensible defaults and constraints.

# variable "region" {
#   description = "The GCP region for resources (e.g. europe-west1)"
#   type        = string
#   default     = "europe-west1"
#
#   validation {
#     condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
#     error_message = "region must be a valid GCP region (e.g. \"europe-west1\")."
#   }
# }
