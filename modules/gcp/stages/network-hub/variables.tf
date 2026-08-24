variable "project_prefix" {
  description = "Prefix used for project naming"
  type        = string
}

variable "hub_vpc_cidr_block" {
  description = "CIDR block for the hub VPC (e.g. \"10.0.0.0/16\"). Required — set via IPAM or per-environment tfvars."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.hub_vpc_cidr_block))
    error_message = "hub_vpc_cidr_block must be a valid CIDR notation."
  }
}

variable "dns_hub_vpc_cidr_block" {
  description = "CIDR block for the DNS hub VPC (e.g. \"10.1.0.0/16\"). Required — must not overlap with hub_vpc_cidr_block."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.dns_hub_vpc_cidr_block))
    error_message = "dns_hub_vpc_cidr_block must be a valid CIDR notation."
  }
}

variable "default_region" {
  description = "Default GCP region for resources"
  type        = string
}

variable "hub_project_id" {
  description = "Project ID for the network hub"
  type        = string
}

variable "dns_project_id" {
  description = "Project ID for the DNS hub"
  type        = string
}

variable "spoke_project_numbers" {
  description = <<-EOT
    Map of spoke project NUMBERS (not IDs) to include in the VPC-SC perimeter.
    The GCP Access Context Manager API requires numeric project numbers prefixed with
    "projects/". Project IDs (e.g. "myorg-dev-host-abc1") are rejected with a
    permission error that is misleading — always pass project numbers here.

    Obtain with: gcloud projects describe <id> --format='value(projectNumber)'
    Or use module.projects.project_numbers from the stages/projects module output.
  EOT
  type        = map(string)
}

variable "org_id" {
  description = <<-EOT
    The GCP organization ID. Accepts either a bare numeric ID (e.g. '123456789012') as returned
    by data.google_organization.org.org_id, or the 'organizations/<id>' prefixed form.
    The module normalizes to the prefixed form internally before passing to VPC-SC.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.org_id)) || can(regex("^organizations/[0-9]+$", var.org_id))
    error_message = "org_id must be either a bare numeric ID (e.g., '123456789012') or 'organizations/<numeric_id>'."
  }
}

variable "folders" {
  description = "Map of folder objects to attach policies to"
  type = map(object({
    id           = string
    name         = string
    display_name = string
  }))
}

variable "internal_domain" {
  description = "Internal domain for private DNS zone (e.g., 'mycompany.com')"
  type        = string
  default     = "internal.local"
}

variable "vpc_sc_access_policy_name" {
  description = <<-EOT
    Bare numeric ID of the existing organisation-level Access Context Manager access policy
    (e.g. '1234567890'). Required when the hub VPC-SC perimeter is enabled.
    Do NOT include the 'accessPolicies/' prefix.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.vpc_sc_access_policy_name == null || can(regex("^[0-9]+$", var.vpc_sc_access_policy_name))
    error_message = "vpc_sc_access_policy_name must be a bare numeric ID (e.g. '1234567890'). Do not include the 'accessPolicies/' prefix."
  }
}

variable "vpc_sc_enable_dry_run" {
  description = <<-EOT
    When true (the default), the hub VPC-SC perimeter logs violations but does NOT block traffic (dry-run/simulation mode).
    When false, the perimeter is ENFORCED.
    Google recommends dry-run first: validate the violation logs, then promote to enforcement by setting this false.
    See docs/known-gaps.md (G11).
  EOT
  type        = bool
  default     = true
}

variable "enable_deletion_protection" {
  description = <<-EOT
    When true (the default), protects hub and DNS VPC resources from accidental deletion via
    terraform destroy. Set to false only during a planned teardown.
    IMPORTANT: Set to false and apply before attempting to destroy the hub network stack.
  EOT
  type        = bool
  default     = true
}

# --- Audit finding G5: VPC-SC perimeter hardening (opt-in) -------------------
# The base perimeter restricts only storage/bigquery/cloudfunctions/run and has
# no ingress policy. The perimeter now defaults to DRY-RUN
# (vpc_sc_enable_dry_run = true, G11), so expanding restricted_services is safe
# to trial first — violations are logged, not blocked. Before PROMOTING to
# enforcement (vpc_sc_enable_dry_run = false), set an ingress policy for the
# automation identity, or the enforced perimeter will block the TFC-run SA from
# managing those services in the spoke projects. Both variables default empty so
# behavior is unchanged until you opt in. Harden by setting BOTH together.
variable "vpc_sc_additional_restricted_services" {
  description = <<-EOT
    Extra service API hostnames to add to the hub data perimeter's restricted_services,
    beyond the base set (storage/bigquery/cloudfunctions/run). Recommended additions once
    an automation ingress policy is in place: logging.googleapis.com, monitoring.googleapis.com,
    cloudkms.googleapis.com, secretmanager.googleapis.com, compute.googleapis.com,
    container.googleapis.com, pubsub.googleapis.com, spanner.googleapis.com, sqladmin.googleapis.com.
    Default [] = unchanged. PREVIEW (not yet validated against a real apply) against a real org — validate under dry-run first.
  EOT
  type        = list(string)
  default     = []
}

variable "vpc_sc_ingress_identities" {
  description = <<-EOT
    Identities (e.g. "serviceAccount:terraform-admin@<admin-project>.iam.gserviceaccount.com")
    granted full ingress into the hub data perimeter — set this to the automation/TFC-run SA
    BEFORE expanding restricted_services or the next enforced apply is blocked. Default [] =
    no ingress policy (unchanged). PREVIEW (not yet validated against a real apply) — validate under dry-run first.
  EOT
  type        = list(string)
  default     = []
}
