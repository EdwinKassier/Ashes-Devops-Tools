# Config-backed variables default to null and are read as local.<name>
# (config.tf). Validations check the EFFECTIVE value, so an unset value fails
# the plan and the error names the config key.

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
    error_message = "landing_zone_config_path is set to \"${var.landing_zone_config_path == null ? "" : var.landing_zone_config_path}\" but no file exists there (relative to this root). Fix the path. In HCP Terraform only ../../../config/landing-zone.yaml or ../../../config/<estate>/landing-zone.yaml passes the policy check; \"\" disables the file in local and test runs only."
  }
}

variable "tfc_organization" {
  description = "Terraform Cloud organization that owns the remote-state workspaces this root reads. Used in every terraform_remote_state config block so state resolves at plan time without cloud credentials. Null = org.tfc.organization from config/landing-zone.yaml."
  type        = string
  default     = null

  # Required only when a remote-state read actually happens (no contract).
  validation {
    condition = (
      (var.organization_contract != null || local.cfg.organization_contract != null) ||
      try(length(coalesce(var.tfc_organization, local.cfg.tfc_organization)) > 0, false)
    )
    error_message = "tfc_organization (config key org.tfc.organization) is required unless an organization_contract (<cloud>.contracts.organization) is supplied."
  }
}

variable "organization_workspace_name" {
  description = "Name of the Terraform Cloud workspace holding the <cloud>-organization root state this root reads."
  type        = string
  default     = "cloud-organization"
}

variable "organization_contract" {
  description = "Stage contract override for the <cloud>-organization layer. When set (or <cloud>.contracts.organization is in the config file), the remote-state read is skipped and these values are used instead. CLONE-ME: tighten the type to the real contract object."
  type        = map(string)
  default     = null
}

# Optional variables — add your cloud's region / enabled-region inputs here,
# config-backed like templates/aws/root/variables.tf (region-shaped validation
# on the effective value, interval repeats kept <= 1000 for the RE2 engine).
