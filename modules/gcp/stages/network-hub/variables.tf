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

variable "hub_zones" {
  description = "Zones of the hub VPC and the DNS anchor VPC (both in default_region), in subnet order: subnet i of each tier takes the i-th CIDR, so the order fixes the subnet CIDRs. Empty (default) = the zones GCP returns for the region, which can change and then replaces subnets. gcp-network-hub requires it when any environment is_production."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for z in var.hub_zones : startswith(z, "${var.default_region}-") && can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", z))]) && length(distinct(var.hub_zones)) == length(var.hub_zones)
    error_message = "hub_zones must list distinct zones of default_region (${var.default_region}), such as ${var.default_region}-a."
  }
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
    Map of environment key to the environment host project NUMBER (not ID). Used for the
    NCC hub auto-accept list and as the default consumer list of the published Secure Web Proxy.
    These projects are NOT in the hub VPC-SC perimeter: each environment host project sits in
    its own environment perimeter (stages/environment), so prod and non-prod never share one.
    Accepts bare numbers or "projects/<number>"; empty values are ignored.

    Obtain with: gcloud projects describe <id> --format='value(projectNumber)'
    Or use module.projects.project_numbers from the stages/projects module output.
  EOT
  type        = map(string)
}

variable "hub_project_number" {
  description = "Numeric project number of the hub project (var.hub_project_id). It and dns_project_number are the only projects in the hub VPC-SC perimeter. Required when vpc_sc_access_policy_name is set."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.hub_project_number == "" || can(regex("^[0-9]+$", var.hub_project_number))
    error_message = "hub_project_number must be a bare numeric project number (no 'projects/' prefix, not a project ID)."
  }
  validation {
    condition     = var.vpc_sc_access_policy_name == null || var.hub_project_number != ""
    error_message = "hub_project_number is required when vpc_sc_access_policy_name is set (the hub perimeter protects the hub and DNS projects)."
  }
}

variable "dns_project_number" {
  description = "Numeric project number of the DNS hub project (var.dns_project_id), protected by the hub VPC-SC perimeter together with the hub project. Required when vpc_sc_access_policy_name is set."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.dns_project_number == "" || can(regex("^[0-9]+$", var.dns_project_number))
    error_message = "dns_project_number must be a bare numeric project number (no 'projects/' prefix, not a project ID)."
  }
  validation {
    condition     = var.vpc_sc_access_policy_name == null || var.dns_project_number != ""
    error_message = "dns_project_number is required when vpc_sc_access_policy_name is set (the hub perimeter protects the hub and DNS projects)."
  }
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
  description = "Name of the private root DNS zone (internal-root), for example 'corp.example.com': lowercase letters, digits and hyphens, at least two labels, no trailing dot. The zone's dns_name is immutable, so changing it on an existing hub replaces the zone and drops every record in it (it needs a destroy_guard override and the records created again)."
  type        = string
  default     = "internal.local"

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.internal_domain)) && length(var.internal_domain) <= 253
    error_message = "internal_domain must be a lowercase DNS name of at least two labels without a trailing dot, for example corp.example.com."
  }
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
    Routes announced: empty advertised_ip_ranges (default) = CUSTOM mode with the ALL_SUBNETS
    group (every hub subnet) plus hybrid_advertised_ranges (the environment CIDRs) and, with
    hybrid DNS forward zones, 35.199.192.0/19 (DEFAULT mode when that list is empty).
    Non-empty advertised_ip_ranges = exactly those ranges plus advertised_groups (default none).
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
    advertised_groups          = optional(list(string), [])
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

variable "hub_private_service_connect" {
  description = "Overrides for the hub VPC's Private Service Connect endpoint for Google APIs (gcp.network.private_service_connect in config). name: 1-20 lower-case letters and numbers, starting with a letter (null = hubvpccorepsc). address: the endpoint's internal IPv4 address, outside every hub subnet range, including the Secure Web Proxy proxy-only and PSC NAT subnets (null = the second-to-last address of the hub CIDR, for example 10.0.255.254)."
  type = object({
    name    = optional(string)
    address = optional(string)
  })
  default  = {}
  nullable = false
}

variable "spoke_peerings" {
  description = "Hub side of the environment VPC peerings (connectivity = peering), keyed by environment key: the spoke network self link and the route exchange from the hub's view. Each entry becomes the peering hub-to-<env> on the hub VPC. Pass only spokes whose network already exists (envs/gcp/network-hub discovers them); the gcp-workload-<env> root creates the spoke side. Empty (default) = no hub-side peerings."
  type = map(object({
    network_self_link    = string
    export_custom_routes = optional(bool, true)
    import_custom_routes = optional(bool, true)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k in keys(var.spoke_peerings) : can(regex("^[a-z]([-a-z0-9]{0,53}[a-z0-9])?$", k))])
    error_message = "spoke_peerings keys must be environment keys usable in the peering name hub-to-<env>: lowercase letters, digits and hyphens, starting with a letter, at most 55 characters."
  }
}

variable "hybrid_advertised_ranges" {
  description = "Prefixes the hub Cloud Routers announce over VPN/Interconnect when vpn.advertised_ip_ranges (or an interconnect's) is empty, next to the ALL_SUBNETS group (every hub subnet): normally every environment CIDR (envs/gcp/network-hub derives them). DEFAULT BGP mode never announces peered environment subnets. With no ranges at all (no environment CIDR, no forward zone) the routers stay in DEFAULT mode (the hub subnets only)."
  type = list(object({
    range       = string
    description = string
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for r in var.hybrid_advertised_ranges : can(cidrhost(r.range, 0))])
    error_message = "hybrid_advertised_ranges entries need a valid CIDR range."
  }
}

variable "hybrid_dns" {
  description = "Hybrid DNS, used only when the VPN or an Interconnect is on. enable_inbound_forwarding (default true) adds an inbound DNS server policy on the hub VPC, so on-premises resolvers can forward the internal domain to its entry-point addresses. forward_zones forwards on-premises domains (dns_name ending with a dot) from the hub VPC to target_ips over the private path. A forward zone may not be internal_domain or a subdomain of it: the internal zone is bound to the hub VPC too."
  type = object({
    enable_inbound_forwarding = optional(bool, true)
    forward_zones = optional(map(object({
      dns_name   = string
      target_ips = list(string)
    })), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for z in values(var.hybrid_dns.forward_zones) : endswith(z.dns_name, ".") && length(z.target_ips) > 0 && alltrue([for ip in z.target_ips : can(regex("^(\\d{1,3}\\.){3}\\d{1,3}$", ip))])])
    error_message = "hybrid_dns.forward_zones entries need a dns_name ending with a dot and at least one IPv4 target_ips address."
  }

  validation {
    condition     = alltrue([for k in keys(var.hybrid_dns.forward_zones) : can(regex("^[a-z]([-a-z0-9]{0,57}[a-z0-9])?$", k))])
    error_message = "hybrid_dns.forward_zones keys name the zone fwd-<key>: lowercase letters, digits and hyphens, starting with a letter, at most 59 characters."
  }

  validation {
    condition = alltrue([for z in values(var.hybrid_dns.forward_zones) :
      lower(z.dns_name) != lower("${var.internal_domain}.") && !endswith(lower(z.dns_name), lower(".${var.internal_domain}."))
    ])
    error_message = "hybrid_dns.forward_zones may not forward internal_domain or a subdomain of it: the internal zone is bound to the hub VPC, two private zones on one network cannot share a DNS name, and a forwarded subdomain would hide part of the internal zone."
  }
}

variable "hub_peering_limit" {
  description = "Most environment peerings the hub VPC may carry. The PEERINGS_PER_NETWORK quota is 25 peerings per network by default; one is kept for the hub's own Private Service Access peering. Raise it only after the quota is raised."
  type        = number
  default     = 24
  nullable    = false

  validation {
    condition     = var.hub_peering_limit >= 1
    error_message = "hub_peering_limit must be at least 1."
  }
}

variable "secure_web_proxy" {
  description = <<-EOT
    Opt-in central egress control (preview): a Secure Web Proxy in the hub with an FQDN allowlist
    (everything else is denied). See stages/net-hub secure_web_proxy for the fields.
    psc_nat_subnet_cidr publishes it to the environments over Private Service Connect;
    consumer_accept_projects empty = the environment host projects (spoke_project_numbers).
    Default: off.
  EOT
  type = object({
    enabled       = optional(bool, false)
    address       = optional(string)
    ports         = optional(list(number), [443])
    allowed_fqdns = optional(list(string), [])
    additional_rules = optional(map(object({
      priority            = number
      action              = string
      session_matcher     = string
      application_matcher = optional(string)
      description         = optional(string)
      enabled             = optional(bool, true)
    })), {})
    certificate_urls         = optional(list(string), [])
    proxy_only_subnet_cidr   = optional(string)
    psc_nat_subnet_cidr      = optional(string)
    consumer_accept_projects = optional(list(string), [])
  })
  default  = {}
  nullable = false
}

variable "alerting" {
  description = "Hub data-plane alert policies (VPN tunnel down, BGP session down, Cloud NAT allocation failures and drops), on by default for the features that exist. notification_channel_ids: existing channel IDs (projects/<project>/notificationChannels/<id>). enabled = false creates none."
  type = object({
    enabled                       = optional(bool, true)
    notification_channel_ids      = optional(list(string), [])
    nat_dropped_packets_threshold = optional(number, 0)
  })
  default  = {}
  nullable = false
}
