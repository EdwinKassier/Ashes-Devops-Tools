variable "project_id" {
  description = "The GCP project ID where the Artifact Registry repositories will be created"
  type        = string

  validation {
    condition     = length(var.project_id) >= 6 && length(var.project_id) <= 30
    error_message = "Project ID must be between 6 and 30 characters"
  }
}

variable "region" {
  description = "The region where the Artifact Registry repositories will be created"
  type        = string
  default     = "us-central1"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid GCP region format (e.g., us-central1)"
  }
}

variable "repositories" {
  description = "Map of repository configurations to create"
  type = map(object({
    description    = string
    format         = optional(string, "DOCKER")
    immutable_tags = optional(bool, true)
  }))
  default = {
    "ashes-flask-repo" = {
      description = "Artifact registry for flask images"
    }
    "ashes-django-repo" = {
      description = "Artifact registry for django images"
    }
    "ashes-fastapi-repo" = {
      description = "Artifact registry for fastapi images"
    }
    "ashes-express-repo" = {
      description = "Artifact registry for express images"
    }
    "ashes-hermes-repo" = {
      description = "Artifact registry for hermes images"
    }
  }
}

variable "labels" {
  description = "Labels to apply to all repositories"
  type        = map(string)
  default = {
    managed-by = "terraform"
  }
}
