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

variable "github_sa_bindings" {
  description = "List of GitHub repository to service account bindings. repository must be 'owner/repo' format. Set repository_id (the immutable numeric GitHub repository ID) to bind on attribute.repository_id (or attribute.repo_ref with github_allowed_refs) instead of the mutable repository name. Set key when service_account_email is unknown until apply."
  type = list(object({
    repository            = string # Format: owner/repo
    repository_id         = optional(string)
    service_account_email = string
    # Optional static for_each key. Set it when service_account_email is only
    # known after apply (e.g. an SA created in the same plan); otherwise the key
    # defaults to "<repository>-<service_account_email>".
    key = optional(string)
  }))
  default = []

  validation {
    condition     = alltrue([for b in var.github_sa_bindings : can(regex("^[a-zA-Z0-9._-]+/[a-zA-Z0-9._-]+$", b.repository))])
    error_message = "Each repository must be in 'owner/repo' format using only alphanumeric characters, hyphens, underscores, and dots (it is embedded in a principalSet URI)."
  }

  validation {
    condition     = alltrue([for b in var.github_sa_bindings : b.repository_id == null || can(regex("^[0-9]+$", b.repository_id))])
    error_message = "repository_id must be the numeric GitHub repository ID (digits only)."
  }
}

variable "github_repository_owner_id" {
  description = "Immutable numeric GitHub owner (org/user) ID (gh api repos/<owner>/<repo> --jq .owner.id). Required when enable_github_provider = true: the provider attribute_condition is exactly assertion.repository_owner_id == \"<id>\", the form the org-policy constraint custom.wifProviderTenantPinned accepts. An org rename or name squat cannot satisfy it."
  type        = string
  default     = null

  validation {
    condition     = var.github_repository_owner_id == null || can(regex("^[0-9]+$", var.github_repository_owner_id))
    error_message = "github_repository_owner_id must be the numeric GitHub owner ID (digits only)."
  }

  validation {
    condition     = !var.enable_github_provider || var.github_repository_owner_id != null
    error_message = "enable_github_provider requires github_repository_owner_id: the provider condition is the owner pin, and a provider without one would trust every GitHub repository."
  }
}

variable "github_allowed_refs" {
  description = "Exact git refs (e.g. [\"refs/heads/main\", \"refs/tags/v1\"]) a GitHub workflow must run from to impersonate a bound SA. When set, every github_sa_bindings entry is bound once per ref on attribute.repo_ref (\"<repository_id>/<ref>\"), so each entry needs repository_id. Empty (default) binds on attribute.repository_id: any ref of the repository. Wildcards are not supported (a principalSet value is an exact match)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for r in var.github_allowed_refs : can(regex("^[A-Za-z0-9_./-]+$", r))])
    error_message = "github_allowed_refs entries may contain only letters, digits, '_', '.', '/' and '-' (no wildcards, quotes or spaces: each is an exact principalSet value)."
  }

  validation {
    condition     = length(var.github_allowed_refs) == 0 || alltrue([for b in var.github_sa_bindings : b.repository_id != null])
    error_message = "github_allowed_refs binds on attribute.repo_ref (\"<repository_id>/<ref>\"), so every github_sa_bindings entry needs repository_id."
  }
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
  description = "GitLab namespace (group path) to restrict access to. Matches the namespace itself or any sub-group under it (namespace_path == X || startsWith(X + '/')), never a sibling sharing the prefix. Interpolated into CEL, so it must not contain single quotes."
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

variable "tfc_organization_id" {
  description = "Optional immutable Terraform Cloud organization ID (org-xxxxxxxx). When set, the provider attribute_condition also pins assertion.terraform_organization_id, so a renamed/re-registered organization name cannot satisfy the trust."
  type        = string
  default     = null

  validation {
    condition     = var.tfc_organization_id == null || can(regex("^org-[A-Za-z0-9]+$", var.tfc_organization_id))
    error_message = "tfc_organization_id must look like org-XXXXXXXX (alphanumeric after the 'org-' prefix)."
  }
}

variable "tfc_project_ids" {
  description = "Optional allow-list of Terraform Cloud project IDs (prj-xxxxxxxx). When non-empty, the provider attribute_condition also requires assertion.terraform_project_id to be one of these, so a workspace created in any other TFC project cannot authenticate."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for p in var.tfc_project_ids : can(regex("^prj-[A-Za-z0-9]+$", p))])
    error_message = "Each tfc_project_ids entry must look like prj-XXXXXXXX (alphanumeric after the 'prj-' prefix)."
  }
}

variable "tfc_sa_bindings" {
  description = <<-EOT
    TFC workspace + run phase to service account bindings. Each entry binds ONE
    run phase ("plan" or "apply") of ONE workspace to a service account, via the
    composite attribute.workspace_phase ("<name>:<phase>") or, when workspace_id
    (ws-xxxxxxxx) is supplied, attribute.workspace_id_phase ("<id>:<phase>").
    (workspace_name, run_phase) pairs must be unique.
  EOT
  type = list(object({
    workspace_name        = string
    workspace_id          = optional(string)
    run_phase             = string
    service_account_email = string
  }))
  default = []

  validation {
    condition     = alltrue([for b in var.tfc_sa_bindings : contains(["plan", "apply"], b.run_phase)])
    error_message = "Each tfc_sa_bindings entry's run_phase must be \"plan\" or \"apply\"."
  }

  validation {
    condition     = alltrue([for b in var.tfc_sa_bindings : can(regex("^[A-Za-z0-9_-]+$", b.workspace_name))])
    error_message = "workspace_name must contain only letters, digits, hyphens and underscores (it is embedded in a principalSet URI)."
  }

  validation {
    condition     = alltrue([for b in var.tfc_sa_bindings : b.workspace_id == null || can(regex("^ws-[A-Za-z0-9]+$", b.workspace_id))])
    error_message = "workspace_id must look like ws-XXXXXXXX (alphanumeric after the 'ws-' prefix)."
  }

  validation {
    condition     = length(distinct([for b in var.tfc_sa_bindings : "${b.workspace_name}:${b.run_phase}"])) == length(var.tfc_sa_bindings)
    error_message = "Each (workspace_name, run_phase) pair may be bound to only one service account."
  }
}

variable "tfc_hostname" {
  description = "HCP Terraform / Terraform Enterprise hostname that issues the dynamic-credential tokens (app.terraform.io, app.eu.terraform.io, or a TFE host)."
  type        = string
  default     = "app.terraform.io"

  validation {
    condition     = can(regex("^[a-z0-9.-]+(:[0-9]+)?$", var.tfc_hostname))
    error_message = "tfc_hostname must be a bare hostname (optionally :port), without scheme or path."
  }
}
