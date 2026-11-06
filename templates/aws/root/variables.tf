# Config-backed variables default to null and are read as local.<name>
# (config.tf). Validations check the EFFECTIVE value, so an unset value fails
# the plan and the error names the config key.

variable "landing_zone_config_path" {
  description = "Path to the single-source landing-zone config (YAML; schema config/landing-zone.example.yaml), absolute or relative to this root. Null = ../../../config/landing-zone.yaml; \"\" disables the lookup. Read only if the file exists; explicit variables win over its values."
  type        = string
  default     = null
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
  description = "Stage contract override for the aws-organization layer. When set (or aws.contracts.organization is in the config file), the aws-organization remote-state read is skipped and these values are used instead."
  type = object({
    account_ids = map(string)
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

  # AWS region names are short (well under the RE2 1000-repeat cap). Shape:
  # <geo>-<direction>-<number>, e.g. eu-west-2, us-east-1, ap-southeast-3.
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[1-9][0-9]?$", coalesce(var.aws_region, local.cfg.aws_region, "eu-west-2")))
    error_message = "aws_region (config key org.regions.aws) must be a valid AWS region name, e.g. eu-west-2."
  }
}

variable "aws_enabled_regions" {
  description = "Regions this root manages resources in. Null = aws.enabled_regions from config/landing-zone.yaml, else the primary region only."
  type        = list(string)
  default     = null
}
