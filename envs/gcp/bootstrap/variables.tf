variable "landing_zone_config_path" {
  description = "Path to the single-source landing-zone config (YAML; schema config/landing-zone.example.yaml), absolute or relative to this root. Null = ../../../config/landing-zone.yaml; \"\" disables the lookup. Read only if the file exists; explicit variables win over its values."
  type        = string
  default     = null
}

variable "project_prefix" {
  description = <<-EOT
    Short prefix prepended to all GCP project IDs to ensure global uniqueness.
    Must start with a lowercase letter; only lowercase letters, digits, and hyphens allowed.
    Keep this to 6 characters or fewer — GCP project IDs are capped at 30 characters and
    the prefix consumes part of that budget. Null = org.prefix from
    config/landing-zone.yaml (shared by every GCP root). The placeholder "my-org" is rejected.
  EOT
  type        = string
  default     = null

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,9}$", coalesce(var.project_prefix, local.cfg.project_prefix, "!unset")))
    error_message = "project_prefix is unset or invalid: set var.project_prefix or org.prefix in config/landing-zone.yaml. It must start with a lowercase letter, contain only lowercase letters, digits, and hyphens, and be 10 characters or fewer."
  }

  validation {
    condition     = coalesce(var.project_prefix, local.cfg.project_prefix, "!unset") != "my-org"
    error_message = "project_prefix is still set to the placeholder 'my-org'. Set it to your organisation's actual identifier before deploying."
  }
}

variable "domain" {
  description = "The domain name of the organization (e.g., 'example.com'). Null = org.domain from config/landing-zone.yaml."
  type        = string
  default     = null

  validation {
    condition     = length(trimspace(coalesce(var.domain, local.cfg.domain, " "))) > 0
    error_message = "domain is unset: set var.domain or org.domain in config/landing-zone.yaml."
  }
}

variable "billing_account" {
  description = "Billing account ID (optional if billing_account_display_name is provided). Null = gcp.billing_account from config/landing-zone.yaml."
  type        = string
  default     = null

  validation {
    condition     = coalesce(var.billing_account, local.cfg.billing_account, var.billing_account_display_name, "!unset") != "!unset"
    error_message = "At least one of billing_account (or gcp.billing_account in config/landing-zone.yaml) or billing_account_display_name must be set."
  }

  validation {
    condition     = !startswith(coalesce(var.billing_account, local.cfg.billing_account, "ok"), "REPLACE_WITH")
    error_message = "billing_account is still the config/landing-zone.example.yaml placeholder: set your billing account ID."
  }
}

variable "billing_account_display_name" {
  description = "Display name of the billing account (used if billing_account ID is not provided)"
  type        = string
  default     = null
}

variable "admin_email" {
  description = "Email address for the organization administrator. Null = gcp.admin_email from config/landing-zone.yaml."
  type        = string
  default     = null

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", coalesce(var.admin_email, local.cfg.admin_email, "!unset")))
    error_message = "admin_email is unset or not a valid email address: set var.admin_email or gcp.admin_email in config/landing-zone.yaml."
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
  description = "Terraform Cloud organization used for dynamic credentials. Null = org.tfc.organization from config/landing-zone.yaml."
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
  description = "Optional map of TFC workspace name -> immutable workspace ID (ws-xxxxxxxx). Workspaces listed here are WIF-bound by ID instead of by (mutable, squattable) name. Populate from the tfc-admin root once the workspaces exist; a check warns when an is_production environment or a control-plane workspace has no entry."
  type        = map(string)
  default     = {}
}

variable "vpc_sc_access_policy_id" {
  description = "Optional numeric ID of the org-wide Access Context Manager policy. Only used with enable_legacy_org_access_policy_grants = true; by default each environment gets its own folder-scoped policy from gcp-organization."
  type        = string
  default     = null
}

variable "enable_legacy_org_access_policy_grants" {
  description = "LEGACY. Grant every workload apply SA policyEditor (plan: policyReader) on the org-wide policy vpc_sc_access_policy_id, which lets any environment edit every perimeter. Default false; enable only while migrating perimeters to the scoped policies."
  type        = bool
  default     = false
}

variable "enable_scoped_access_policies" {
  description = "Give the organization stage SAs the Access Context Manager rights needed to create one folder-scoped access policy per environment (gcp-organization enable_scoped_access_policies). Default true; keep the two in step."
  type        = bool
  default     = true
}

variable "enable_org_level_folder_iam_delegation" {
  description = "LEGACY. Bind the projects-apply conditional folderIamAdmin at the org node (every folder). Default false: gcp-organization binds it per target folder. Enable only to bridge a migration."
  type        = bool
  default     = false
}

variable "enable_pam" {
  description = "Grant the organization stage SAs Privileged Access Manager rights so gcp-organization can manage the just-in-time org-admin entitlement (gcp-organization enable_pam). Default false."
  type        = bool
  default     = false
}

variable "enable_phase0_admin_impersonation" {
  description = "Let user:<admin_email> impersonate the terraform-admin SA for the phase-0 first apply. Set false on pass 2 (once gcp-bootstrap runs through TFC dynamic credentials) so no standing human path to the bootstrap apply identity remains."
  type        = bool
  default     = true
}

variable "guardrail_owner_mode" {
  description = "IAM deny-policy ownership. \"separate\" (default): a dedicated <prefix>-guardrails-apply SA is the only automation identity with roles/iam.denyAdmin, so the organization apply SA cannot delete the containment policy that constrains it. \"organization\": legacy, the organization apply SA holds denyAdmin."
  type        = string
  default     = "separate"
}

variable "guardrail_owner_members" {
  description = "Principals (ideally one PAM-gated group) allowed to impersonate the guardrails SA in separate mode. Empty = nobody until set."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for m in var.guardrail_owner_members : can(regex("^(group|user|serviceAccount|principal|principalSet):", m)) && !can(regex("(?i)(replace|example\\.(com|org|net)|your-domain|\\.invalid$)", m))])
    error_message = "guardrail_owner_members must be IAM principals (group:/user:/serviceAccount:/principal:/principalSet:) and must not be placeholders (REPLACE, example.com, your-domain, .invalid)."
  }
}

variable "enable_principal_access_boundary" {
  description = "Grant the organization stage SAs the rights the gcp-organization principal access boundary policy needs (gcp-organization enable_principal_access_boundary). Default false."
  type        = bool
  default     = false
}

variable "environments" {
  description = "Map of application environment definitions. Here each key gets a <prefix>-wl-<env>-plan/-apply SA pair bound to TFC workspace gcp-workload-<env>, and is_production (default false) marks the environments whose workspaces must be WIF-bound by immutable ID (tfc_workspace_ids). Null = gcp.environments from config/landing-zone.yaml (the single source shared by every GCP root and tfc-admin)."
  type = map(object({
    display_name            = string
    region                  = string
    cidr_block              = string
    budget_monthly_limit    = number
    iam_group_role_bindings = map(set(string))
    labels                  = optional(map(string), {})
    is_production           = optional(bool, false)
  }))
  default = null

  validation {
    condition     = var.environments != null || length(local.cfg.environments) > 0
    error_message = "environments is unset: define gcp.environments in config/landing-zone.yaml or set var.environments."
  }

  # Environment keys become project/workspace keys (e.g. "<env>-host",
  # "gcp-workload-<env>"). "shared" is reserved for the hub/DNS projects: a
  # right-wins merge() would silently replace them with an environment named
  # "shared". Keys must also be a valid lowercase token.
  validation {
    condition     = alltrue([for k in(var.environments != null ? keys(var.environments) : keys(local.cfg.environments)) : k != "shared" && can(regex("^[a-z][a-z0-9-]{0,14}$", k))])
    error_message = "environments keys must be lowercase tokens (^[a-z][a-z0-9-]{0,14}$) and must not be the reserved key \"shared\"."
  }

  validation {
    condition     = alltrue([for c in(var.environments != null ? [for e in values(var.environments) : e.cidr_block] : [for e in values(local.cfg.environments) : e.cidr_block]) : can(cidrnetmask(c))])
    error_message = "Each environment's cidr_block must be valid CIDR notation, e.g. 10.10.0.0/16."
  }
}

variable "default_region" {
  description = "Default region for resources. Null = org.regions.gcp from config/landing-zone.yaml, else europe-west2."
  type        = string
  default     = null
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

variable "tfc_hostname" {
  description = "HCP Terraform / Terraform Enterprise hostname issuing the dynamic-credential tokens the TFC WIF pool trusts (app.terraform.io, app.eu.terraform.io or a TFE host)."
  type        = string
  default     = "app.terraform.io"
}
