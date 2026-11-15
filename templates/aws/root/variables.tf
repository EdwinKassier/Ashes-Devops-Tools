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
    error_message = "tfc_organization (config key org.tfc.organization) is required unless an organization_contract (aws.contracts.organization) is supplied."
  }
}

variable "organization_workspace_name" {
  description = "Name of the Terraform Cloud workspace holding the aws-organization root state this root reads account_ids from."
  type        = string
  default     = "aws-organization"
}

variable "organization_contract" {
  description = "aws-organization stage contract (FAST-style override), the same type in every aws root: organization_id (o-xxxxxxxxxx), organization_root_id (r-xxxx), management_account_id, ou_ids (OU name => OU ID), account_ids (account key => 12-digit ID), account_role_arns (account key => cross-account role ARN). This root needs: account_ids. When set, the aws-organization remote state is NOT read. Null = aws.contracts.organization from config/landing-zone.yaml, else the contract output of the organization_workspace_name workspace."
  type = object({
    organization_id       = optional(string)
    organization_root_id  = optional(string)
    management_account_id = optional(string)
    ou_ids                = optional(map(string), {})
    account_ids           = map(string)
    account_role_arns     = optional(map(string), {})
  })
  default = null

  validation {
    condition     = var.organization_contract == null || alltrue([for id in values(try(var.organization_contract.account_ids, {})) : can(regex("^[0-9]{12}$", id))])
    error_message = "organization_contract.account_ids values must be 12-digit AWS account IDs."
  }
}

variable "aws_region" {
  description = "Primary AWS region for the default provider (e.g. eu-west-2). Null = org.regions.aws from config/landing-zone.yaml, else eu-west-2."
  type        = string
  default     = null

  # The canonical AWS region regex (scripts/check-consistency.sh): commercial
  # and China names (<geo>-<direction>-<number>, e.g. eu-west-2), GovCloud
  # (us-gov-west-1) and the European Sovereign Cloud (eusc-de-east-1).
  validation {
    condition     = can(regex("^([a-z]{2}|us-gov|eusc-[a-z]{2})-[a-z]+-[1-9][0-9]?$", coalesce(var.aws_region, local.cfg.aws_region, "eu-west-2")))
    error_message = "aws_region (config key org.regions.aws) must be a valid AWS region name, e.g. eu-west-2."
  }
}

variable "aws_enabled_regions" {
  description = "Regions this root manages resources in. Null = aws.enabled_regions from config/landing-zone.yaml, else the primary region only."
  type        = list(string)
  default     = null
}
