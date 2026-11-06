variable "project_prefix" {
  description = "Short prefix prepended to all GCP project IDs. Keep in sync with the gcp-organization root."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,9}$", var.project_prefix))
    error_message = "project_prefix must start with a lowercase letter, contain only lowercase letters, digits, and hyphens, and be 10 characters or fewer."
  }
}

variable "default_region" {
  description = "Default region for resources"
  type        = string
  default     = "europe-west1"
}

variable "environments" {
  description = "Map of application environment definitions. Only the keys are used here, to look up each environment's host project number for the hub spoke wiring. Keep in sync with the gcp-organization root."
  type = map(object({
    display_name            = string
    region                  = string
    cidr_block              = string
    budget_monthly_limit    = number
    iam_group_role_bindings = map(set(string))
    labels                  = optional(map(string), {})
    is_production           = optional(bool, false)
  }))

  # Environment keys become project/workspace keys (e.g. "<env>-host",
  # "gcp-workload-<env>"). "shared" is reserved for the hub/DNS projects: a
  # right-wins merge() would silently replace them with an environment named
  # "shared". Keys must also be a valid lowercase token.
  validation {
    condition     = alltrue([for k in keys(var.environments) : k != "shared" && can(regex("^[a-z][a-z0-9-]{0,14}$", k))])
    error_message = "environments keys must be lowercase tokens (^[a-z][a-z0-9-]{0,14}$) and must not be the reserved key \"shared\"."
  }

  validation {
    condition     = alltrue([for e in values(var.environments) : can(cidrnetmask(e.cidr_block))])
    error_message = "Each environment's cidr_block must be valid CIDR notation, e.g. 10.10.0.0/16. Keep the environments map identical across the GCP roots."
  }
}

variable "hub_vpc_cidr_block" {
  description = "CIDR block for the hub network VPC. Must not overlap with DNS hub or spoke CIDRs."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.hub_vpc_cidr_block))
    error_message = "hub_vpc_cidr_block must be a valid CIDR notation (e.g. \"10.0.0.0/16\")."
  }
}

variable "dns_hub_vpc_cidr_block" {
  description = "CIDR block for the DNS hub VPC. Must not overlap with hub_vpc_cidr_block or spoke CIDRs."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.dns_hub_vpc_cidr_block))
    error_message = "dns_hub_vpc_cidr_block must be a valid CIDR notation (e.g. \"10.1.0.0/16\")."
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
  description = "When true (default), the hub VPC-SC perimeter logs violations but does NOT block (dry-run). Set to false to ENFORCE, only after validating the violation logs. See docs/known-gaps.md (G11) and docs/runbooks/production-hardening.md."
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
  description = "Terraform Cloud organization that owns the upstream workspaces read via remote state."
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
