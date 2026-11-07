/**
 * Copyright 2023 Ashes
 *
 * net-hub Module - Variables
 */

variable "project_id" {
  description = "The GCP project ID that owns the network (6-30 characters, lowercase alphanumeric and hyphens, must start with a letter)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be 6-30 characters, start with a lowercase letter, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "region" {
  description = "The primary GCP region of the network (e.g., 'us-central1', 'europe-west1')."
  type        = string
  default     = "us-central1"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a valid GCP region name (e.g., 'us-central1', 'europe-west1')."
  }
}

variable "labels" {
  description = "Labels applied to every labelable resource."
  type        = map(string)
  default     = {}
}

variable "deletion_protection" {
  description = "Guard the VPC and subnet stack with a prevent_destroy terraform_data resource and enable VPC deletion protection. To deprovision deliberately, first run terraform state rm on the network module guard."
  type        = bool
  default     = false
}

variable "project_prefix" {
  description = "Prefix for derived resource names (e.g. 'ashes-dev'). Must start with a letter and contain only lowercase letters, digits, and hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.project_prefix))
    error_message = "project_prefix must start with a lowercase letter and contain only lowercase letters, digits, and hyphens."
  }
}

variable "network" {
  description = <<-EOT
    The VPC and its three-tier zonal subnet layout.
    name and cidr_block are required. Pin explicit_zones for production: when
    empty, zones are discovered from GCP and a change in the returned zone set
    re-derives the subnet CIDRs (replacing subnets). subnet_cidrs lists are
    index-aligned with the zones; an empty list derives that tier from
    cidr_block. secondary_ranges (GKE Pods and Services) attach to the private
    tier, keyed by zone. shared_vpc_host makes the hub project a
    Shared VPC host (default true). flow_logs sets the subnet flow-log sampling.
  EOT
  type = object({
    name           = string
    cidr_block     = string
    explicit_zones = optional(list(string), [])
    subnet_cidrs = optional(object({
      public   = optional(list(string), [])
      private  = optional(list(string), [])
      database = optional(list(string), [])
    }), {})
    secondary_ranges = optional(map(list(object({
      range_name    = string
      ip_cidr_range = string
    }))), {})
    shared_vpc_host = optional(bool, true)
    flow_logs = optional(object({
      aggregation_interval = optional(string, "INTERVAL_5_SEC")
      sampling             = optional(number, 0.5)
    }), {})
  })

  validation {
    condition     = can(cidrnetmask(var.network.cidr_block)) ? cidrhost(var.network.cidr_block, 0) == split("/", var.network.cidr_block)[0] : false
    error_message = "network.cidr_block must be valid CIDR notation without host bits set (e.g. \"10.0.0.0/16\")."
  }
  validation {
    condition     = alltrue([for z in var.network.explicit_zones : can(regex("^[a-z]+-[a-z]+[0-9]-[a-z]$", z))])
    error_message = "Each entry in network.explicit_zones must be a valid GCP zone name (e.g. 'us-central1-a')."
  }
}

variable "firewall" {
  description = "Baseline tier firewall: rule logging, the IAP SSH/RDP allow rule, and the ports opened public to compute and compute to database. api_gateway_source_ranges and database_egress_target_service_accounts apply only to the network firewall policy (firewall_mode both / policy)."
  type = object({
    enable_logging     = optional(bool, true)
    enable_iap_access  = optional(bool, true)
    compute_tier_ports = optional(list(string), ["8080", "8443", "3000"])
    database_ports     = optional(list(string), ["3306", "5432", "6379"])
    # Network firewall policy only (firewall_mode both / policy).
    api_gateway_source_ranges               = optional(list(string), [])
    database_egress_target_service_accounts = optional(list(string), [])
  })
  default  = {}
  nullable = false
}

variable "nat" {
  description = "Cloud NAT (and its Cloud Router) for the private and database tiers. Set enabled = false for a network with no egress need."
  type = object({
    enabled            = optional(bool, true)
    ip_allocate_option = optional(string, "AUTO_ONLY")
    log_filter         = optional(string, "ERRORS_ONLY")
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["AUTO_ONLY", "MANUAL_ONLY"], var.nat.ip_allocate_option)
    error_message = "nat.ip_allocate_option must be AUTO_ONLY or MANUAL_ONLY."
  }
  validation {
    condition     = contains(["ERRORS_ONLY", "TRANSLATIONS_ONLY", "ALL"], var.nat.log_filter)
    error_message = "nat.log_filter must be ERRORS_ONLY, TRANSLATIONS_ONLY, or ALL."
  }
}

variable "private_service_access" {
  description = "Private Service Access range (private-IP Cloud SQL, Memorystore and other Google-managed services peer through it)."
  type = object({
    enabled       = optional(bool, true)
    name          = optional(string, "google-managed-services")
    prefix_length = optional(number, 16)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.private_service_access.prefix_length >= 16 && var.private_service_access.prefix_length <= 29
    error_message = "private_service_access.prefix_length must be between 16 and 29 inclusive."
  }
}

variable "private_service_connect" {
  description = "Private Service Connect endpoint for Google APIs; target is 'all-apis' or 'vpc-sc'."
  type = object({
    enabled = optional(bool, true)
    target  = optional(string, "all-apis")
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["all-apis", "vpc-sc"], var.private_service_connect.target)
    error_message = "private_service_connect.target must be 'all-apis' or 'vpc-sc'."
  }
}

variable "hierarchical_firewall_policies" {
  description = "Hierarchical firewall policies owned by the hub, keyed by policy name. parent is the owning folders/<id> or organizations/<id>; associations lists the folders or organization the policy is attached to."
  type = map(object({
    parent      = string
    description = optional(string, "Managed by Terraform")
    rules = optional(list(object({
      priority       = number
      action         = string
      direction      = string
      description    = optional(string)
      disabled       = optional(bool, false)
      enable_logging = optional(bool, false)
      layer4_configs = list(object({
        ip_protocol = string
        ports       = optional(list(string))
      }))
      src_ip_ranges           = optional(list(string))
      src_region_codes        = optional(list(string))
      dest_ip_ranges          = optional(list(string))
      dest_region_codes       = optional(list(string))
      target_networks         = optional(list(string))
      target_service_accounts = optional(list(string))
    })), [])
    associations   = optional(list(string), [])
    enable_logging = optional(bool, true)
  }))
  default  = {}
  nullable = false
}

variable "vpn" {
  description = <<-EOT
    HA VPN to an on-premises or other-cloud peer gateway, off by default.
    tunnel_count is 2 for HA (production) or 1 for testing. peer_gateway_ips
    lists the peer interface IPv4 addresses (one per tunnel). local_ips and
    peer_ips are the BGP link-local addresses. The pre-shared key is the separate
    sensitive vpn_shared_secret input.
  EOT
  type = object({
    enabled          = optional(bool, false)
    tunnel_count     = optional(number, 2)
    router_asn       = optional(number, 64512)
    peer_asn         = optional(number, 64513)
    peer_gateway_ips = optional(list(string), [])
    local_ips        = optional(list(string), ["169.254.0.1", "169.254.0.3"])
    peer_ips         = optional(list(string), ["169.254.0.2", "169.254.0.4"])
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

variable "ncc" {
  description = "Network Connectivity Center hub, off by default (spokes then use VPC peering). preset_topology: STAR (edge spokes reach the center only; the peering-equivalent) or MESH. Immutable once created. name defaults to <project_prefix>-ncc-hub. export_private_service_access adds a producer VPC spoke for the hub PSA peering (when PSA is enabled). auto_accept_projects (project IDs or numbers) adopts the spoke group to auto-accept spokes from those projects; empty = spokes from other projects wait for a manual accept."
  type = object({
    enabled                       = optional(bool, false)
    name                          = optional(string)
    preset_topology               = optional(string, "STAR")
    export_psc                    = optional(bool, false)
    export_private_service_access = optional(bool, true)
    auto_accept_projects          = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["STAR", "MESH"], var.ncc.preset_topology)
    error_message = "ncc.preset_topology must be STAR or MESH."
  }
}

variable "vpn_shared_secret" {
  description = "HA VPN pre-shared key. Required when vpn.enabled is true; inject it from Secret Manager or a sensitive workspace variable, not a plaintext tfvars file."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = !var.vpn.enabled || (var.vpn_shared_secret != null && var.vpn_shared_secret != "")
    error_message = "vpn_shared_secret must be set (non-null, non-empty) when vpn.enabled is true."
  }
}

variable "interconnects" {
  description = "Cloud Interconnect VLAN attachments on the hub network, keyed by attachment name (Dedicated or Partner)."
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

variable "vpc_service_controls" {
  description = "VPC Service Controls perimeters, keyed by perimeter name. protected_projects takes project NUMBERS, not IDs."
  type = map(object({
    # organization_id must be the FULL resource form 'organizations/<numeric-id>'
    # (Access Context Manager's access-policy parent requires this form). NOTE:
    # this diverges from every other org-id input in the repo (governance/tags,
    # governance/cloud-audit-logs, stages/organization var.org_id) which take the
    # BARE numeric id. Callers prefix the bare org_id output here accordingly.
    # See docs: the vpc-sc module is the sole outlier; a future normalization
    # would have vpc-sc accept the bare id and prefix internally.
    organization_id      = string
    access_policy_name   = optional(string)
    create_access_policy = optional(bool, false)
    perimeter_title      = string
    description          = optional(string, "Managed by Terraform")
    perimeter_type       = optional(string, "PERIMETER_TYPE_REGULAR")
    protected_projects   = optional(list(string), [])
    restricted_services  = optional(list(string), [])
    access_levels = optional(list(object({
      name               = string
      title              = string
      description        = optional(string)
      combining_function = optional(string, "AND")
      conditions = list(object({
        ip_subnetworks = optional(list(string))
        members        = optional(list(string))
        negate         = optional(bool, false)
        regions        = optional(list(string))
      }))
    })), [])
    ingress_policies = optional(list(object({
      identity_type = optional(string)
      identities    = optional(list(string))
      sources = optional(list(object({
        access_level = optional(string)
        resource     = optional(string)
      })))
      resources = optional(list(string))
      operations = optional(list(object({
        service_name = string
        method_selectors = optional(list(object({
          method     = optional(string)
          permission = optional(string)
        })))
      })))
    })), [])
    egress_policies = optional(list(object({
      identity_type = optional(string)
      identities    = optional(list(string))
      resources     = optional(list(string))
      operations = optional(list(object({
        service_name = string
        method_selectors = optional(list(object({
          method     = optional(string)
          permission = optional(string)
        })))
      })))
    })), [])
    enable_dry_run             = optional(bool, true)
    enable_deletion_protection = optional(bool, true)
    # Staged dry-run delta on an ENFORCED perimeter (see network/vpc-sc). null = same as enforced.
    dry_run_restricted_services = optional(list(string))
    dry_run_ingress_policies = optional(list(object({
      identity_type = optional(string)
      identities    = optional(list(string))
      sources = optional(list(object({
        access_level = optional(string)
        resource     = optional(string)
      })))
      resources = optional(list(string))
      operations = optional(list(object({
        service_name = string
        method_selectors = optional(list(object({
          method     = optional(string)
          permission = optional(string)
        })))
      })))
    })))
    dry_run_egress_policies = optional(list(object({
      identity_type = optional(string)
      identities    = optional(list(string))
      resources     = optional(list(string))
      operations = optional(list(object({
        service_name = string
        method_selectors = optional(list(object({
          method     = optional(string)
          permission = optional(string)
        })))
      })))
    })))
  }))
  default  = {}
  nullable = false
}

variable "firewall_mode" {
  description = "How the baseline tier firewall is enforced (network/tiered-vpc firewall_mode). legacy: tag-based VPC firewall rules (default). both: the VPC rules plus a global network firewall policy keyed on tier subnet CIDRs. policy: the network firewall policy only. See docs/runbooks/gcp-firewall-policy-migration.md."
  type        = string
  default     = "legacy"
  nullable    = false

  validation {
    condition     = contains(["legacy", "both", "policy"], var.firewall_mode)
    error_message = "firewall_mode must be one of legacy, both or policy."
  }
}

variable "firewall_policy_enforcement_order" {
  description = "Network firewall policy enforcement order on the VPC: BEFORE_CLASSIC_FIREWALL or AFTER_CLASSIC_FIREWALL. null derives it from firewall_mode (policy sets BEFORE_CLASSIC_FIREWALL; legacy and both leave the API default AFTER_CLASSIC_FIREWALL). Updates the network in place. WARNING: switching from both to policy with this unset flips the order in the same apply that deletes the legacy rules; set it explicitly."
  type        = string
  default     = null

  validation {
    condition     = var.firewall_policy_enforcement_order == null ? true : contains(["BEFORE_CLASSIC_FIREWALL", "AFTER_CLASSIC_FIREWALL"], var.firewall_policy_enforcement_order)
    error_message = "firewall_policy_enforcement_order must be null, BEFORE_CLASSIC_FIREWALL or AFTER_CLASSIC_FIREWALL."
  }
}
