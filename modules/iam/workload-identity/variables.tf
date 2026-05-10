variable "project_id" {
  description = "The GCP project ID where the Workload Identity Pool will be created"
  type        = string
}

variable "pool_id" {
  description = "The ID for the Workload Identity Pool"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}[a-z0-9]$", var.pool_id))
    error_message = "Pool ID must be 4-32 characters, start with a letter, and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "display_name" {
  description = "Display name for the Workload Identity Pool"
  type        = string
}

variable "description" {
  description = "Description of the Workload Identity Pool"
  type        = string
  default     = "Workload Identity Pool for external authentication"
}

variable "disabled" {
  description = "Whether the pool is disabled"
  type        = bool
  default     = false
}

# GitHub Provider Configuration
variable "enable_github_provider" {
  description = "Enable GitHub Actions OIDC provider"
  type        = bool
  default     = false
}

variable "github_organization" {
  description = "GitHub organization to restrict access to (optional). Must contain only alphanumeric characters and hyphens — value is interpolated into a CEL expression."
  type        = string
  default     = null

  validation {
    condition     = var.github_organization == null || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]*$", var.github_organization))
    error_message = "github_organization must contain only alphanumeric characters and hyphens (no single quotes or special characters — this value is embedded in a CEL condition)."
  }
}

variable "github_sa_bindings" {
  description = "List of GitHub repository to service account bindings. repository must be 'owner/repo' format — value is interpolated into a CEL expression."
  type = list(object({
    repository            = string # Format: owner/repo
    service_account_email = string
  }))
  default = []

  validation {
    condition     = alltrue([for b in var.github_sa_bindings : can(regex("^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$", b.repository))])
    error_message = "Each repository must be in 'owner/repo' format using only alphanumeric characters, hyphens, underscores, and dots (no single quotes — this value is embedded in a CEL condition)."
  }
}

variable "github_allowed_refs" {
  description = "List of allowed git refs for GitHub Actions (e.g., ['refs/heads/main', 'refs/heads/release/*']). When set, only workflows triggered from these refs can authenticate."
  type        = list(string)
  default     = []
}

variable "github_attribute_condition_override" {
  description = "Full custom attribute condition for GitHub provider. When set, overrides the default condition based on organization and allowed_refs."
  type        = string
  default     = null
}

# GitLab Provider Configuration
variable "enable_gitlab_provider" {
  description = "Enable GitLab CI OIDC provider"
  type        = bool
  default     = false
}

variable "gitlab_url" {
  description = "GitLab instance URL (e.g., https://gitlab.com)"
  type        = string
  default     = "https://gitlab.com"
}

variable "gitlab_namespace" {
  description = "GitLab namespace to restrict access to (optional). Value is interpolated into a CEL startsWith() expression — must not contain single quotes."
  type        = string
  default     = null

  validation {
    condition     = var.gitlab_namespace == null || can(regex("^[a-zA-Z0-9._/-]+$", var.gitlab_namespace))
    error_message = "gitlab_namespace must contain only alphanumeric characters, hyphens, underscores, dots, and forward slashes (no single quotes — this value is embedded in a CEL condition)."
  }
}

variable "gitlab_sa_bindings" {
  description = "List of GitLab project to service account bindings"
  type = list(object({
    project_path          = string # Format: group/project
    service_account_email = string
  }))
  default = []
}

# AWS Provider Configuration
variable "enable_aws_provider" {
  description = "Enable AWS OIDC provider for cross-cloud authentication"
  type        = bool
  default     = false
}

variable "aws_account_id" {
  description = "AWS account ID to restrict access to (12-digit numeric AWS account ID)"
  type        = string
  default     = null

  validation {
    condition     = var.aws_account_id == null || can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit numeric AWS account ID."
  }
}

# Terraform Cloud Provider Configuration
variable "enable_tfc_provider" {
  description = "Enable Terraform Cloud OIDC provider for Dynamic Credentials"
  type        = bool
  default     = false
}

variable "tfc_organization" {
  description = "Terraform Cloud organization name. Value is interpolated into a CEL expression — must not contain single quotes."
  type        = string
  default     = null

  validation {
    condition     = var.tfc_organization == null || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]*$", var.tfc_organization))
    error_message = "tfc_organization must contain only alphanumeric characters and hyphens (no single quotes — this value is embedded in a CEL condition)."
  }
}

variable "tfc_sa_bindings" {
  description = "List of TFC workspace to service account bindings"
  type = list(object({
    workspace_name        = string
    project_name          = optional(string, "*")
    service_account_email = string
  }))
  default = []
}
