variable "landing_zone_config_path" {
  description = "Path to the single-source landing-zone config (YAML; schema config/landing-zone.example.yaml), relative to this root (a .yaml or .yml file inside the repository). Null = ../../../config/landing-zone.yaml; \"\" disables the lookup. When set, the file must exist (the plan fails otherwise); the default path is read only if the file exists; explicit variables win over its values."
  type        = string
  default     = null

  # SEC-1: only a relative .yaml/.yml path that stays inside the repository, so
  # the loader's file() cannot read a file on the runner (/proc/self/environ).
  validation {
    condition = var.landing_zone_config_path == null || var.landing_zone_config_path == "" || (
      can(regex("^[A-Za-z0-9_./-]+\\.ya?ml$", coalesce(var.landing_zone_config_path, "x"))) &&
      !startswith(coalesce(var.landing_zone_config_path, "x"), "/") &&
      length([for s in split("/", dirname("./${coalesce(var.landing_zone_config_path, "x")}/_")) : s if s == ".."]) <= 3
    )
    error_message = "landing_zone_config_path must be a relative path to a .yaml or .yml file inside the repository (no leading /, at most 3 leading ../ from this root): an absolute or escaping path could read a file on the runner."
  }

  # IAC-3: a path that is set must name a file, so a typo does not silently
  # drop the whole config and fall back to built-in defaults.
  validation {
    condition     = var.landing_zone_config_path == null || var.landing_zone_config_path == "" || startswith(coalesce(var.landing_zone_config_path, "/"), "/") || fileexists("${path.root}/${coalesce(var.landing_zone_config_path, "x")}")
    error_message = "landing_zone_config_path is set to \"${var.landing_zone_config_path == null ? "" : var.landing_zone_config_path}\" but no file exists there (relative to this root). Fix the path (in HCP Terraform only config/landing-zone.yaml or config/<estate>/landing-zone.yaml passes the policy check; \"\" disables the file in local and test runs only)."
  }
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
  description = "Environment keys with is_production (default false here; required on every gcp.environments entry in config/landing-zone.yaml). A production environment turns admin containment on. Null = gcp.environments from config/landing-zone.yaml (the single source shared by every GCP root and tfc-admin); other attributes are ignored here."
  type = map(object({
    is_production = optional(bool, false)
  }))
  default = null

  validation {
    condition     = var.environments != null || length(local.cfg.environments_missing_is_production) == 0
    error_message = "Every gcp.environments entry in config/landing-zone.yaml must set is_production: true or false; the environment name is not read. Missing or invalid: ${join(", ", local.cfg.environments_missing_is_production)}."
  }
}

variable "enable_admin_containment" {
  description = "Create the admin-containment deny policy. Org-wide, it blocks sink update/delete, exclusion changes, log-bucket delete and VPC-SC perimeter mutation. Scoped by the containment/protected tag to the audit store, it blocks bucket delete/IAM change/untag, object delete, key-version destroy/disable and key IAM change. containment_exempt_principals (break-glass) are exempt. Null (default) = gcp.admin_containment from config, else ON whenever an environment is_production or a break-glass principal is set, as in gcp-organization (which creates and binds the tag). Needs a break-glass principal."
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
