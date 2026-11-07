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
    See docs/known-gaps.md.
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

# --- VPC-SC perimeter hardening (opt-in) ------------------------------------
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

variable "vpc_sc_dry_run_additional_restricted_services" {
  description = "Services to TRIAL in a staged dry-run spec on top of the enforced hub perimeter (base set + vpc_sc_additional_restricted_services). Only meaningful when vpc_sc_enable_dry_run = false: status keeps enforcing, the dry-run spec logs what these extra services would block. Default null = no staged spec."
  type        = list(string)
  default     = null
}

variable "enable_ncc_hub" {
  description = "Create a Network Connectivity Center hub in the hub project, with the hub VPC as its center spoke (and a producer spoke for its Private Service Access peering). Environment VPCs join it with connectivity = ncc. False (default) = VPC peering only."
  type        = bool
  default     = false
  nullable    = false
}

variable "ncc_preset_topology" {
  description = "NCC hub preset topology: STAR (environment spokes reach the hub VPC, not each other; the peering-equivalent) or MESH (every spoke reaches every other). Immutable once the hub exists."
  type        = string
  default     = "STAR"
  nullable    = false

  validation {
    condition     = contains(["STAR", "MESH"], var.ncc_preset_topology)
    error_message = "ncc_preset_topology must be STAR or MESH."
  }
}

variable "vpn" {
  description = <<-EOT
    HA VPN to an on-premises or other-cloud peer gateway, off by default.
    tunnel_count is 2 for HA (production) or 1 for testing. peer_gateway_ips
    lists the peer interface IPv4 addresses (one per tunnel). local_ips and
    peer_ips are the BGP link-local addresses. The pre-shared key is the separate
    write-only vpn_shared_secret_wo input. site_to_site_data_transfer lets on-premises sites exchange traffic through the NCC hybrid spoke. With enable_ncc_hub, the tunnels also join the NCC hub as a hybrid spoke.
  EOT
  type = object({
    enabled                    = optional(bool, false)
    tunnel_count               = optional(number, 2)
    router_asn                 = optional(number, 64512)
    peer_asn                   = optional(number, 64513)
    peer_gateway_ips           = optional(list(string), [])
    local_ips                  = optional(list(string), ["169.254.0.1", "169.254.0.3"])
    peer_ips                   = optional(list(string), ["169.254.0.2", "169.254.0.4"])
    site_to_site_data_transfer = optional(bool, false)
    advertised_ip_ranges = optional(list(object({
      range       = string
      description = string
    })), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains([1, 2], var.vpn.tunnel_count)
    error_message = "vpn.tunnel_count must be 1 or 2."
  }
}

variable "vpn_shared_secret_wo" {
  description = "Write-only HA VPN pre-shared key: sent to the API at apply time, never stored in state or plan. Supply it from an ephemeral source (an ephemeral resource, or a TFC variable). Required when vpn.enabled is true."
  type        = string
  default     = null
  sensitive   = true
  ephemeral   = true

  validation {
    condition     = !var.vpn.enabled || (var.vpn_shared_secret_wo != null && var.vpn_shared_secret_wo != "")
    error_message = "vpn_shared_secret_wo must be set (non-null, non-empty) when vpn.enabled is true."
  }
}

variable "vpn_shared_secret_wo_version" {
  description = "Rotation counter for vpn_shared_secret_wo. Write-only values are not diffed: increment this to push a changed key."
  type        = number
  default     = 1
  nullable    = false
}

variable "interconnects" {
  description = "Cloud Interconnect VLAN attachments on the hub network (gcp.network.interconnect in config), keyed by attachment name (Dedicated or Partner)."
  type = map(object({
    region            = string
    interconnect_type = optional(string, "PARTNER")
    router_name       = string
    router_asn        = optional(number, 64512)
    create_router     = optional(bool, true)

    # Dedicated interconnect settings
    interconnect_self_link = optional(string)
    vlan_tag               = optional(number)
    bandwidth              = optional(string, "BPS_10G")

    # Partner interconnect settings
    edge_availability_domain = optional(string, "AVAILABILITY_DOMAIN_1")

    # Common settings
    mtu           = optional(number, 1440)
    admin_enabled = optional(bool, true)
    encryption    = optional(string, "NONE")

    # BGP settings
    create_bgp_peer    = optional(bool, true)
    interface_ip_range = optional(string)
    peer_ip_address    = optional(string)
    peer_asn           = optional(number, 65000)
    enable_bfd         = optional(bool, false)

    advertised_ip_ranges = optional(list(object({
      range       = string
      description = optional(string)
    })), [])
  }))
  default  = {}
  nullable = false
}

variable "hub_additional_regions" {
  description = "Opt-in extra regions of the hub VPC (gcp.network.additional_regions in config), keyed by region name: subnet_cidrs (public, private, database; one regional subnet per tier, no overlap with the primary hub subnets or another region), optional secondary_ranges for the private subnet, and nat (default true: a Cloud Router and Cloud NAT in the region). The DNS anchor VPC stays single-region. Empty (default) = single-region hub."
  type = map(object({
    subnet_cidrs = object({
      public   = string
      private  = string
      database = string
    })
    secondary_ranges = optional(list(object({
      range_name    = string
      ip_cidr_range = string
    })), [])
    nat = optional(bool, true)
  }))
  default  = {}
  nullable = false
}
