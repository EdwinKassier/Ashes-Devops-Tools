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

variable "kms_key_name" {
  description = "Customer-managed KMS key name used to encrypt repository contents. Omit for Google-managed encryption."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_name == null || can(regex("^projects/[^/]+/locations/[^/]+/keyRings/[^/]+/cryptoKeys/[^/]+$", var.kms_key_name))
    error_message = "kms_key_name must be a valid KMS key resource name: projects/<project>/locations/<location>/keyRings/<ring>/cryptoKeys/<key>."
  }
}

variable "repositories" {
  description = "Map of repository configurations to create. Valid format values: DOCKER, MAVEN, NPM, PYTHON, APT, YUM, GOOGET, KFP, GENERIC."
  type = map(object({
    description    = string
    format         = optional(string, "DOCKER")
    immutable_tags = optional(bool, true)
  }))

  validation {
    condition = alltrue([
      for k, v in var.repositories :
      contains(["DOCKER", "MAVEN", "NPM", "PYTHON", "APT", "YUM", "GOOGET", "KFP", "GENERIC"], v.format)
    ])
    error_message = "Each repository format must be one of: DOCKER, MAVEN, NPM, PYTHON, APT, YUM, GOOGET, KFP, GENERIC."
  }

  validation {
    condition = alltrue([
      for k, v in var.repositories :
      can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$|^[a-z0-9]$", k))
    ])
    error_message = "Repository map keys must be valid Artifact Registry repository IDs: lowercase letters, digits, and hyphens; starts with a letter or digit; 1-63 characters."
  }

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
