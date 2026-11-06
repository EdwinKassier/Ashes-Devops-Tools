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

variable "default_region" {
  description = "Default region for resources. Null = org.regions.gcp from config/landing-zone.yaml, else europe-west2."
  type        = string
  default     = null
}

variable "environments" {
  description = "Map of application environment definitions. Only the keys are used here, to look up each environment's host project number for the hub spoke wiring. Null = gcp.environments from config/landing-zone.yaml (the single source shared by every GCP root and tfc-admin)."
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

variable "hub_vpc_cidr_block" {
  description = "CIDR block for the hub network VPC. Must not overlap with DNS hub or spoke CIDRs. Null = gcp.network.hub_cidr_block from config/landing-zone.yaml."
  type        = string
  default     = null

  validation {
    condition     = can(cidrnetmask(coalesce(var.hub_vpc_cidr_block, local.cfg.hub_vpc_cidr_block, "!unset")))
    error_message = "hub_vpc_cidr_block is unset or not valid CIDR notation (e.g. 10.0.0.0/16): set var.hub_vpc_cidr_block or gcp.network.hub_cidr_block in config/landing-zone.yaml."
  }
}

variable "dns_hub_vpc_cidr_block" {
  description = "CIDR block for the DNS hub VPC. Must not overlap with hub_vpc_cidr_block or spoke CIDRs. Null = gcp.network.dns_hub_cidr_block from config/landing-zone.yaml."
  type        = string
  default     = null

  validation {
    condition     = can(cidrnetmask(coalesce(var.dns_hub_vpc_cidr_block, local.cfg.dns_hub_vpc_cidr_block, "!unset")))
    error_message = "dns_hub_vpc_cidr_block is unset or not valid CIDR notation (e.g. 10.1.0.0/16): set var.dns_hub_vpc_cidr_block or gcp.network.dns_hub_cidr_block in config/landing-zone.yaml."
  }
}

variable "vpc_sc_access_policy_name" {
  description = "Bare numeric ID of the org-level Access Context Manager access policy for the hub VPC-SC perimeter (e.g. '1234567890'). Optional — if null, no hub perimeter is created. Do NOT include the 'accessPolicies/' prefix."
  type        = string
  default     = null

  validation {
    condition     = var.vpc_sc_access_policy_name == null || can(regex("^[0-9]+$", var.vpc_sc_access_policy_name))
    error_message = "vpc_sc_access_policy_name must be a bare numeric ID (e.g. '1234567890'). Do not include the 'accessPolicies/' prefix."
  }
}

variable "vpc_sc_enable_dry_run" {
  description = "When true (default), the hub VPC-SC perimeter logs violations but does NOT block (dry-run). Set to false to ENFORCE, only after validating the violation logs. See docs/known-gaps.md and docs/runbooks/production-hardening.md."
  type        = bool
  default     = true
}

variable "vpc_sc_additional_restricted_services" {
  description = "Extra service hostnames to add to the hub data perimeter. Default [] = unchanged. Set the automation-ingress identities before expanding under enforcement. PREVIEW — validate under dry-run first."
  type        = list(string)
  default     = []
}

variable "vpc_sc_dry_run_additional_restricted_services" {
  description = "Services to trial in a staged dry-run spec on top of the ENFORCED hub perimeter (only meaningful with vpc_sc_enable_dry_run = false). Status keeps enforcing; the dry-run spec logs what these would block. Default null = no staged spec."
  type        = list(string)
  default     = null
}

variable "vpc_sc_ingress_identities" {
  description = "Automation identities granted ingress into the hub data perimeter, e.g. the TFC-run SA. Set BEFORE expanding restricted_services under enforcement. Default [] = no ingress policy."
  type        = list(string)
  default     = []
}

variable "terraform_admin_email" {
  description = "Terraform admin SA email the providers impersonate. Read from the gcp-bootstrap output; set it on this workspace to match."
  type        = string
  default     = null

  validation {
    condition     = var.terraform_admin_email == null || can(regex("^[^@]+@[^@]+\\.iam\\.gserviceaccount\\.com$", var.terraform_admin_email))
    error_message = "terraform_admin_email must be a GCP service account email (ends in .iam.gserviceaccount.com) or null."
  }
}

variable "tfc_organization" {
  description = "Terraform Cloud organization that owns the upstream workspaces read via remote state. Null = org.tfc.organization from config/landing-zone.yaml."
  type        = string
  default     = null
}

variable "organization_workspace_name" {
  description = "Name of the gcp-organization TFC workspace (read via remote state for folders and org_id)."
  type        = string
  default     = "gcp-organization"
}

variable "projects_workspace_name" {
  description = "Name of the gcp-projects TFC workspace (read via remote state for host project IDs and numbers)."
  type        = string
  default     = "gcp-projects"
}

# Stage contract overrides (FAST-style): when set (here or as gcp.contracts.<layer>
# in config/landing-zone.yaml) the matching remote-state read is skipped.
variable "organization_contract" {
  description = "gcp-organization stage contract: org_id and folders (key => {id, name, display_name}). Null = gcp.contracts.organization from config/landing-zone.yaml, else read from the gcp-organization workspace's remote state."
  type = object({
    org_id = string
    folders = map(object({
      id           = string
      name         = string
      display_name = string
    }))
  })
  default = null
}

variable "projects_contract" {
  description = "gcp-projects stage contract: project_ids and project_numbers (project key => value; needs shared-hub, shared-dns and every <env>-host). Null = gcp.contracts.projects from config/landing-zone.yaml, else read from the gcp-projects workspace's remote state."
  type = object({
    project_ids     = map(string)
    project_numbers = map(string)
  })
  default = null
}
