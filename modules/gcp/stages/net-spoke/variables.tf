/**
 * Copyright 2023 Ashes
 *
 * net-spoke Module - Variables
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

variable "additional_regions" {
  description = "Opt-in extra regions of this VPC, keyed by region name (passed to network/tiered-vpc): subnet_cidrs (public, private, database; one regional subnet per tier, no overlap with the primary subnets or another region), optional secondary_ranges for the region's private subnet, and nat (default true): a Cloud Router <network.name>-router-<region> and Cloud NAT <network.name>-nat-<region> for the region's private and database subnets, with the primary nat settings (created only when nat.enabled). PSA, PSC, VPN, DNS and VPC-SC stay single-region or global. Empty (default) = single-region, nothing changes."
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
    tier, keyed by zone. shared_vpc_host makes the project a
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
  description = "Baseline tier firewall: rule logging, the IAP SSH/RDP allow rule, and the ports opened public to compute and compute to database, plus additional_rules (VPC firewall rules keyed by rule name). api_gateway_source_ranges and database_egress_target_service_accounts apply only to the network firewall policy (firewall_mode both / policy)."
  type = object({
    enable_logging     = optional(bool, true)
    enable_iap_access  = optional(bool, true)
    compute_tier_ports = optional(list(string), ["8080", "8443", "3000"])
    database_ports     = optional(list(string), ["3306", "5432", "6379"])
    # Network firewall policy only (firewall_mode both / policy).
    api_gateway_source_ranges               = optional(list(string), [])
    database_egress_target_service_accounts = optional(list(string), [])
    additional_rules = optional(map(object({
      direction   = optional(string, "INGRESS")
      description = optional(string)
      priority    = optional(number, 1000)
      allow_rules = optional(list(object({
        protocol = string
        ports    = optional(list(string))
      })), [])
      deny_rules = optional(list(object({
        protocol = string
        ports    = optional(list(string))
      })), [])
      source_ranges = optional(list(string))
      target_tags   = optional(list(string))
      source_tags   = optional(list(string))
    })), {})
  })
  default  = {}
  nullable = false
}

variable "nat" {
  description = "Cloud NAT (and its Cloud Router). Set enabled = false for a network with no egress need. include_private_subnets: NAT the private tier (null, the default, = true unless egress_proxy.enabled, which sends private-tier egress through the hub proxy instead). include_database_subnets (default false): NAT the database tier; leave it off so a database VM has no internet path even when it lacks the database network tag. When no tier is NATed, no NAT or router is created."
  type = object({
    enabled                  = optional(bool, true)
    ip_allocate_option       = optional(string, "AUTO_ONLY")
    log_filter               = optional(string, "ERRORS_ONLY")
    include_private_subnets  = optional(bool)
    include_database_subnets = optional(bool, false)
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

variable "peerings" {
  description = "VPC peerings from this network, keyed by peering name (for example the spoke-to-hub peering)."
  type = map(object({
    peer_network           = string
    create_reverse_peering = optional(bool, true)
    export_custom_routes   = optional(bool, false)
    import_custom_routes   = optional(bool, false)
  }))
  default  = {}
  nullable = false
}

variable "connectivity" {
  description = "How the VPC reaches the hub. peering (default): VPC peering per peerings entry. ncc: a Network Connectivity Center spoke on ncc.hub_id, with peerings ignored. Switching an existing spoke deletes its peering; see docs/runbooks/gcp-peering-to-ncc-migration.md."
  type        = string
  default     = "peering"
  nullable    = false

  validation {
    condition     = contains(["peering", "ncc"], var.connectivity)
    error_message = "connectivity must be peering or ncc."
  }
}

variable "ncc" {
  description = "NCC spoke settings, used when connectivity = ncc. hub_id: the network/ncc-hub id. group: edge (STAR hub) or default (MESH hub). Export ranges filter the subnet ranges the hub learns (empty = every subnet, additional_regions included; a non-empty include_export_ranges must also cover the additional-region CIDRs or the hub will not learn them). export_private_service_access adds a producer VPC spoke for the PSA peering (when PSA is enabled)."
  type = object({
    hub_id                        = optional(string)
    group                         = optional(string, "edge")
    include_export_ranges         = optional(list(string), [])
    exclude_export_ranges         = optional(list(string), [])
    export_private_service_access = optional(bool, true)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.connectivity != "ncc" || var.ncc.hub_id != null
    error_message = "ncc.hub_id is required when connectivity = ncc (the gcp-network-hub contract hub_network.ncc_hub_id)."
  }
  validation {
    condition     = contains(["edge", "default"], var.ncc.group)
    error_message = "ncc.group must be edge (STAR hub) or default (MESH hub); center is reserved for the hub VPC."
  }
}

variable "dns_zones" {
  description = "Cloud DNS zones hosted in this project, keyed by zone name. Private zones bind to this VPC; set peering_network for a peering zone that resolves through another VPC (for example the hub DNS anchor). Query logging is always on."
  type = map(object({
    dns_name        = string
    visibility      = string
    description     = optional(string)
    dnssec_enabled  = optional(bool, false)
    peering_network = optional(string)
    records = optional(list(object({
      name    = string
      type    = string
      ttl     = number
      rrdatas = list(string)
    })), [])
  }))
  default  = {}
  nullable = false
}

variable "edge" {
  description = <<-EOT
    Edge security for the environment. cloud_armor is the project-level Cloud
    Armor WAF policy named <project_prefix>-security-policy (OWASP, Log4Shell
    and adaptive DDoS protection). custom_rules entries use either an IP match
    (versioned_expr SRC_IPS_V1 plus config.src_ip_ranges) or a CEL expr, never
    both. Attach the policy to load balancers via the security_policy_self_link
    output.
  EOT
  type = object({
    cloud_armor = optional(object({
      enabled             = optional(bool, true)
      owasp_rules         = optional(bool, true)
      adaptive_protection = optional(bool, true)
      log4j_protection    = optional(bool, true)
      owasp_sensitivity   = optional(number, 2)
      custom_rules = optional(map(object({
        action      = string
        priority    = number
        description = optional(string)
        match_conditions = object({
          # IP-based match. Set versioned_expr AND config, or set expr — never both.
          versioned_expr = optional(string)
          config = optional(object({
            src_ip_ranges = list(string)
          }))
          # CEL expression match. Mutually exclusive with versioned_expr + config.
          expr = optional(string)
        })
        rate_limit_options = optional(object({
          threshold_count     = number
          interval_sec        = number
          conform_action      = optional(string)
          exceed_action       = optional(string)
          enforce_on_key      = optional(string)
          enforce_on_key_type = optional(string)
        }))
      })), {})
    }), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains([1, 2, 3, 4], var.edge.cloud_armor.owasp_sensitivity)
    error_message = "edge.cloud_armor.owasp_sensitivity must be 1, 2, 3, or 4."
  }
}

variable "flow_logs_export" {
  description = <<-EOT
    Export of VPC flow logs to BigQuery and/or Cloud Storage through a log sink,
    encrypted with a dedicated CMEK key. Off by default. When enabled, either set
    create_bigquery_dataset = true (the sink destination is then derived from
    bigquery_dataset_id) or give an explicit destination URI.
  EOT
  type = object({
    enabled                 = optional(bool, false)
    sink_name               = optional(string, "vpc-flow-logs-sink")
    destination             = optional(string, "")
    create_bigquery_dataset = optional(bool, false)
    bigquery_dataset_id     = optional(string, "vpc_flow_logs")
    bigquery_location       = optional(string, "US")
    create_storage_bucket   = optional(bool, false)
    storage_bucket_name     = optional(string, "")
    storage_location        = optional(string, "US")
    retention_days          = optional(number, 90)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.flow_logs_export.enabled || var.flow_logs_export.create_bigquery_dataset || var.flow_logs_export.destination != ""
    error_message = "flow_logs_export.destination must be set when flow_logs_export.enabled is true and create_bigquery_dataset is false."
  }
}

variable "shared_vpc_service_projects" {
  description = "Map of service projects to attach to this host project (ignored unless network.shared_vpc_host is true)"
  type = map(object({
    deletion_policy = optional(string, "ABANDON")
    subnet_iam_bindings = optional(list(object({
      subnet = string
      region = string
      member = string
    })), [])
    grant_network_user_to_all_subnets = optional(bool, false)
    network_user_members              = optional(list(string), [])
    network_viewer_members            = optional(list(string), [])
    enable_gke_permissions            = optional(bool, false)
  }))
  default  = {}
  nullable = false
}

variable "vpc_service_controls" {
  description = "Map of VPC Service Controls perimeters to create"
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

variable "egress_proxy" {
  description = <<-EOT
    Opt-in central egress (preview): a Private Service Connect endpoint in this VPC for the hub
    Secure Web Proxy (stages/net-hub secure_web_proxy with psc_nat_subnet_cidr). service_attachment
    is the hub output secure_web_proxy.service_attachment_id (this project must be in the hub's
    consumer_accept_projects). The endpoint takes an address from the first primary-region private
    subnet (address pins it). global_access lets other regions of this VPC use it. Enabling it also
    drops the private tier from Cloud NAT unless nat.include_private_subnets says otherwise, so
    private-tier workloads reach the internet only through the proxy (HTTPS_PROXY=<endpoint>:<port>).
  EOT
  type = object({
    enabled            = optional(bool, false)
    service_attachment = optional(string)
    address            = optional(string)
    global_access      = optional(bool, false)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.egress_proxy.enabled || can(regex("^projects/[^/]+/regions/[^/]+/serviceAttachments/[^/]+$", coalesce(var.egress_proxy.service_attachment, "-")))
    error_message = "egress_proxy.service_attachment must be a service attachment ID of the form projects/<project>/regions/<region>/serviceAttachments/<name> when egress_proxy.enabled is true."
  }
}

variable "alerting" {
  description = "Cloud NAT alert policies (allocation failures and OUT_OF_RESOURCES packet drops) in this project, on by default whenever a NAT exists. notification_channel_ids are existing channel IDs (projects/<project>/notificationChannels/<id>); empty = the policies still open incidents in the console but notify no one. enabled = false creates none."
  type = object({
    enabled                       = optional(bool, true)
    notification_channel_ids      = optional(list(string), [])
    nat_dropped_packets_threshold = optional(number, 0)
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for c in var.alerting.notification_channel_ids : can(regex("^projects/[^/]+/notificationChannels/[^/]+$", c))])
    error_message = "alerting.notification_channel_ids entries must look like projects/<project>/notificationChannels/<id>."
  }
}
