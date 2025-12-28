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
  description = "GitHub organization to restrict access to (optional)"
  type        = string
  default     = null
}

variable "github_sa_bindings" {
  description = "List of GitHub repository to service account bindings"
  type = list(object({
    repository            = string # Format: owner/repo
    service_account_email = string
  }))
  default = []
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
  description = "GitLab namespace to restrict access to (optional)"
  type        = string
  default     = null
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
  description = "AWS account ID to restrict access to"
  type        = string
  default     = null
}
