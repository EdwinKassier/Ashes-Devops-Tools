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
