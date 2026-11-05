variable "project_prefix" {
  description = <<-EOT
    Short prefix prepended to all GCP project IDs to ensure global uniqueness.
    Must start with a lowercase letter; only lowercase letters, digits, and hyphens allowed.
    Keep this to 6 characters or fewer — GCP project IDs are capped at 30 characters and
    the prefix consumes part of that budget.
    Set this to your organisation's identifier (e.g. "acme", "xyz-co"). Do NOT use the
    default value "my-org" in a real deployment.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,9}$", var.project_prefix))
    error_message = "project_prefix must start with a lowercase letter, contain only lowercase letters, digits, and hyphens, and be 10 characters or fewer."
  }

  validation {
    condition     = var.project_prefix != "my-org"
    error_message = "project_prefix is still set to the placeholder 'my-org'. Set it to your organisation's actual identifier before deploying."
  }
}

variable "domain" {
  description = "The domain name of the organization (e.g., 'example.com')"
  type        = string
}

variable "billing_account" {
  description = "Billing account ID (optional if billing_account_display_name is provided)"
  type        = string
  default     = null

  validation {
    condition     = var.billing_account != null || var.billing_account_display_name != null
    error_message = "At least one of billing_account or billing_account_display_name must be set."
  }
}

variable "billing_account_display_name" {
  description = "Display name of the billing account (used if billing_account ID is not provided)"
  type        = string
  default     = null
}

variable "admin_email" {
  description = "Email address for the organization administrator"
  type        = string

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.admin_email))
    error_message = "admin_email must be a valid email address."
  }
}

variable "github_org" {
  description = "GitHub organization name. Only used when enable_github_wif = true."
  type        = string
  default     = null
}

variable "github_repo" {
  description = "GitHub repository name (without org prefix). Only used when enable_github_wif = true."
  type        = string
  default     = null
}

variable "enable_github_wif" {
  description = "Create the GitHub Actions WIF pool (default false — no workflow uses GCP OIDC). When true it trusts github_repository_id/github_repository_owner_id on refs/heads/main and binds ONLY the read-only organization plan SA."
  type        = bool
  default     = false
}

variable "github_repository_id" {
  description = "Immutable numeric GitHub repository ID (GET /repos/<owner>/<repo> -> .id). Required when enable_github_wif = true."
  type        = string
  default     = null
}

variable "github_repository_owner_id" {
  description = "Immutable numeric GitHub owner ID (GET /repos/<owner>/<repo> -> .owner.id). Required when enable_github_wif = true."
  type        = string
  default     = null
}

variable "tfc_organization" {
  description = "Terraform Cloud organization used for dynamic credentials"
  type        = string
  default     = null
}

variable "enable_tfc_oidc" {
  description = "Whether to provision Workload Identity Federation pools for Terraform Cloud OIDC. Set to false if using a different CI/CD system."
  type        = bool
  default     = true
}

variable "tfc_organization_id" {
  description = "Optional immutable TFC organization ID (org-xxxxxxxx) pinned in the WIF provider condition in addition to the organization name."
  type        = string
  default     = null
}

variable "tfc_project_ids" {
  description = "Optional allow-list of TFC project IDs (prj-xxxxxxxx) holding the GCP workspaces. When set, tokens from workspaces in other TFC projects are rejected."
  type        = list(string)
  default     = []
}

variable "tfc_workspace_ids" {
  description = "Optional map of TFC workspace name -> immutable workspace ID (ws-xxxxxxxx). Workspaces listed here are WIF-bound by ID instead of by (mutable, squattable) name. Populate from the tfc-admin root once the workspaces exist."
  type        = map(string)
  default     = {}
}

variable "vpc_sc_access_policy_id" {
  description = "Optional numeric Access Context Manager policy ID. When set, workload apply SAs get policyEditor (plan SAs policyReader) on this policy only, so gcp-workload-<env> can manage its perimeter without an org-level role."
  type        = string
  default     = null
}

variable "environments" {
  description = "Map of application environment definitions. Only the keys are used here (each key gets a <prefix>-wl-<env>-plan/-apply SA pair bound to TFC workspace gcp-workload-<env>); the full objects are consumed by the gcp-organization root."
  type = map(object({
    display_name            = string
    region                  = string
    cidr_block              = string
    budget_monthly_limit    = number
    iam_group_role_bindings = map(set(string))
    labels                  = optional(map(string), {})
  }))

  validation {
    condition     = alltrue([for e in values(var.environments) : can(cidrnetmask(e.cidr_block))])
    error_message = "Each environment's cidr_block must be valid CIDR notation, e.g. 10.10.0.0/16. Keep the environments map identical across the GCP roots."
  }
}

variable "default_region" {
  description = "Default region for resources"
  type        = string
  default     = "europe-west1"
}

variable "terraform_admin_email" {
  description = <<-EOT
    OPTIONAL service account for the providers to impersonate — for LOCAL human
    runs only (e.g. terraform-admin@<admin-project-id>.iam.gserviceaccount.com
    for a phase-0 re-apply). Leave null (the default) in Terraform Cloud: TFC
    dynamic credentials already authenticate each run as the phase-specific
    plan/apply SA (TFC_GCP_PLAN/APPLY_SERVICE_ACCOUNT_EMAIL), and a plan SA
    cannot (and must not) impersonate the admin SA.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.terraform_admin_email == null || can(regex("^[^@]+@[^@]+\\.iam\\.gserviceaccount\\.com$", var.terraform_admin_email))
    error_message = "terraform_admin_email must be a GCP service account email (ends in .iam.gserviceaccount.com) or null."
  }
}
