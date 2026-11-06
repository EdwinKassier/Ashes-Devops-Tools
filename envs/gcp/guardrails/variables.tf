variable "landing_zone_config_path" {
  description = "Path to the single-source landing-zone config (YAML; schema config/landing-zone.example.yaml), absolute or relative to this root. Null = ../../../config/landing-zone.yaml; \"\" disables the lookup. Read only if the file exists; explicit variables win over its values."
  type        = string
  default     = null
}

variable "domain" {
  description = "The domain name of the organization (e.g. acme.com); the org node the deny policies attach to is resolved from it. Null = org.domain from config/landing-zone.yaml."
  type        = string
  default     = null

  validation {
    condition     = length(trimspace(coalesce(var.domain, local.cfg.domain, " "))) > 0
    error_message = "domain is unset: set var.domain or org.domain in config/landing-zone.yaml."
  }
}

variable "project_prefix" {
  description = "Landing-zone prefix, used only for the provider default labels. Null = org.prefix from config/landing-zone.yaml."
  type        = string
  default     = null

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,9}$", coalesce(var.project_prefix, local.cfg.project_prefix, "!unset")))
    error_message = "project_prefix is unset or invalid: set var.project_prefix or org.prefix in config/landing-zone.yaml (lowercase letter first, then lowercase letters, digits or hyphens, 10 characters or fewer)."
  }
}

variable "environments" {
  description = "Environment keys with is_production (default false). A production environment turns admin containment on. Null = gcp.environments from config/landing-zone.yaml (the single source shared by every GCP root and tfc-admin); other attributes are ignored here."
  type = map(object({
    is_production = optional(bool, false)
  }))
  default = null
}

variable "enable_admin_containment" {
  description = "Create the admin-containment deny policy. Org-wide, it blocks sink update/delete, exclusion changes, log-bucket delete and VPC-SC perimeter mutation. Scoped by the containment/protected tag to the audit store, it blocks bucket delete/IAM change/untag, object delete, key-version destroy/disable and key IAM change. containment_exempt_principals (break-glass) are exempt. Null (default) = gcp.admin_containment from config, else ON whenever an environment is_production, as in gcp-organization (which creates and binds the tag). Needs a break-glass principal."
  type        = bool
  default     = null
}

variable "containment_exempt_principals" {
  description = "Break-glass principals exempt from the admin-containment deny policy, as IAM v2 principal identifiers (e.g. principalSet://goog/group/break-glass@acme.com). Empty (default) = principalSet://goog/group/<gcp.break_glass_group> from config. Placeholder values (REPLACE-ME, your-domain, example.com, .invalid) are rejected."
  type        = list(string)
  default     = []

  validation {
    condition     = !anytrue([for p in var.containment_exempt_principals : can(regex("(?i)(replace-me|your-domain|example\\.(com|org|net)|\\.invalid$|changeme)", p))])
    error_message = "containment_exempt_principals still contains a placeholder (REPLACE-ME / your-domain / example.com / .invalid). Set your real break-glass group before enabling admin containment."
  }
}

variable "enable_principal_access_boundary" {
  description = "Also deny update, delete and unbind of the automation principal access boundary to all but break-glass. Null (default) = gcp.principal_access_boundary from config/landing-zone.yaml, the key gcp-organization reads for the boundary itself, else false. Set the config key rather than this variable so the two cannot drift."
  type        = bool
  default     = null
}

variable "iam_deny_policies" {
  description = "Extra IAM deny policies at the org node, applied next to the containment policy: a coarse, allow-independent backstop blocking specific permissions for specific principals regardless of roles (deny before allow). Default [] = none."
  type = list(object({
    name         = string
    display_name = optional(string)
    rules = list(object({
      description           = optional(string)
      denied_principals     = list(string)
      denied_permissions    = list(string)
      exception_principals  = optional(list(string), [])
      exception_permissions = optional(list(string), [])
      denial_condition = optional(object({
        expression  = string
        title       = optional(string)
        description = optional(string)
      }))
    }))
  }))
  default = []
}
