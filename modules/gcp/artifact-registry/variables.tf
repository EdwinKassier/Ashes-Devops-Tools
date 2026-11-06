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

  validation {
    condition     = can(regex("^[a-z]+(-[a-z]+[0-9]+)?$", var.region))
    error_message = "Region must be a valid GCP location (e.g., us-central1, europe-west1, or a multi-region like us/europe/asia)."
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
  description = <<-EOT
    Map of repository configurations to create. Valid format values: DOCKER, MAVEN,
    NPM, PYTHON, APT, YUM, GOOGET, KFP, GENERIC.
    `cleanup_policies` is keyed by policy id; each has `action` (DELETE or KEEP) and
    either a `condition` (tag_state TAGGED/UNTAGGED/ANY, tag/version/package name
    prefixes, older_than/newer_than durations such as "2592000s") or
    `most_recent_versions` (keep_count). `cleanup_policy_dry_run` (default false)
    only logs what would be deleted.
  EOT
  type = map(object({
    description               = string
    format                    = optional(string, "DOCKER")
    immutable_tags            = optional(bool, true)
    allow_snapshot_overwrites = optional(bool, false)
    version_policy            = optional(string, "VERSION_POLICY_UNSPECIFIED")
    cleanup_policy_dry_run    = optional(bool, false)
    cleanup_policies = optional(map(object({
      action = string
      condition = optional(object({
        tag_state             = optional(string)
        tag_prefixes          = optional(list(string))
        version_name_prefixes = optional(list(string))
        package_name_prefixes = optional(list(string))
        older_than            = optional(string)
        newer_than            = optional(string)
      }))
      most_recent_versions = optional(object({
        package_name_prefixes = optional(list(string))
        keep_count            = optional(number)
      }))
    })), {})
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

  validation {
    condition = alltrue(flatten([
      for k, v in var.repositories : [
        for pk, p in v.cleanup_policies :
        contains(["DELETE", "KEEP"], p.action) && ((p.condition != null) != (p.most_recent_versions != null))
      ]
    ]))
    error_message = "Each cleanup policy needs action DELETE or KEEP and exactly one of condition or most_recent_versions."
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

variable "enable_vulnerability_scanning" {
  description = "Scan DOCKER images automatically on push (Artifact Analysis). Sets each DOCKER repository's vulnerability_scanning_config to INHERITED (DISABLED when false) and, with enable_container_scanning_api, enables containerscanning.googleapis.com. Scanning is billed per image."
  type        = bool
  default     = true
}

variable "enable_container_scanning_api" {
  description = "Enable containerscanning.googleapis.com on project_id when enable_vulnerability_scanning is true. Set false when the caller already manages project APIs (disable_on_destroy is false either way)."
  type        = bool
  default     = true
}
