locals {
  # data.google_organization.org.org_id returns a bare numeric string (e.g. "123456789012").
  # The VPC-SC module requires the "organizations/<id>" prefix form.
  # Accept both inputs and normalize here so callers don't need to manually prefix.
  org_id_normalized = can(regex("^organizations/", var.org_id)) ? var.org_id : "organizations/${var.org_id}"

  # Safe accessor for the "shared" folder in the folders map.
  # Using try() rather than direct indexing (var.folders["shared"]) avoids a
  # tflint false-positive evaluation error when linting with no default value for
  # var.folders, while retaining a clear precondition error if the key is absent at apply time.
  shared_folder = try(var.folders["shared"], null)

  # Audit M (network gaps): the SSH/RDP-from-internet deny must cover EVERY
  # folder (shared + each environment folder), not just shared. The policy is
  # owned by the shared folder and associated with all folders from
  # gcp-organization's folders output (keys: shared + environment keys).
  firewall_association_targets = distinct([
    for k in sort(keys(var.folders)) : var.folders[k].name
    if try(var.folders[k].name, "") != ""
  ])

  # The NCC spoke group auto-accepts spokes from every environment host
  # project (bare numbers; empty entries dropped).
  ncc_auto_accept_projects = sort(distinct(compact([for n in values(var.spoke_project_numbers) : trimprefix(n, "projects/")])))

  # The hub perimeter holds the hub and DNS projects only. Environment host
  # projects each sit in their own environment perimeter: a project can be in
  # only one regular perimeter of an access policy, and one shared perimeter
  # would let prod and non-prod exchange data freely once enforced.
  hub_perimeter_projects = sort(distinct(compact([var.hub_project_number, var.dns_project_number])))

  # The published proxy accepts the environment host projects unless the
  # caller lists consumers explicitly.
  secure_web_proxy = merge(var.secure_web_proxy, {
    consumer_accept_projects = length(var.secure_web_proxy.consumer_accept_projects) > 0 ? var.secure_web_proxy.consumer_accept_projects : local.ncc_auto_accept_projects
  })

  # Base restricted services of the hub perimeter. vpc_sc_dry_run_additional_restricted_services
  # stages a dry-run delta on top (null = no staged spec; see network/vpc-sc).
  hub_base_restricted_services = distinct(concat([
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "cloudfunctions.googleapis.com",
    "run.googleapis.com"
  ], var.vpc_sc_additional_restricted_services))

  # ── Hybrid routes and DNS (ARC-12) ──────────────────────────────────────
  hybrid_enabled = var.vpn.enabled || length(var.interconnects) > 0

  # DEFAULT BGP mode announces the hub VPC's own subnets only, never the
  # peered environment ranges, so on-premises cannot reach the environments
  # (https://docs.cloud.google.com/network-connectivity/docs/router/concepts/advertised-routes).
  # With no explicit ranges the routers move to CUSTOM mode with the
  # ALL_SUBNETS group (every hub subnet: what DEFAULT announced, including the
  # inbound DNS entry points, which are hub subnet addresses) plus every
  # environment CIDR. Forward zones add 35.199.192.0/19, the source range of
  # Cloud DNS forwarded queries, which on-premises must route back over the
  # VPN/Interconnect
  # (https://docs.cloud.google.com/dns/docs/zones/forwarding-zones).
  hybrid_derived_ranges = [
    for r in concat(
      var.hybrid_advertised_ranges,
      length(var.hybrid_dns.forward_zones) > 0 ? [{ range = "35.199.192.0/19", description = "Cloud DNS forwarding source" }] : [],
    ) : { range = r.range, description = r.description }
  ]
  vpn_explicit_ranges = length(var.vpn.advertised_ip_ranges) > 0
  vpn_effective = merge(var.vpn, {
    advertised_groups    = local.vpn_explicit_ranges ? var.vpn.advertised_groups : ["ALL_SUBNETS"]
    advertised_ip_ranges = local.vpn_explicit_ranges ? var.vpn.advertised_ip_ranges : local.hybrid_derived_ranges
  })
  # The interconnect router keeps ALL_SUBNETS in CUSTOM mode by itself
  # (network/interconnect advertised_groups default).
  interconnects_effective = {
    for k, ic in var.interconnects : k => merge(ic, {
      advertised_ip_ranges = length(ic.advertised_ip_ranges) > 0 ? [for r in ic.advertised_ip_ranges : { range = r.range, description = r.description }] : local.hybrid_derived_ranges
    })
  }
}

# Hub network (the "pipes"): net-hub composition on the 'net-hub' project
# created in the shared environment. Formerly module.hub_network (stages/host);
# see moved.tf for the state migration.
module "hub" {
  source = "../net-hub"

  project_id          = var.hub_project_id
  project_prefix      = var.project_prefix
  region              = var.default_region
  deletion_protection = var.enable_deletion_protection
  additional_regions  = var.hub_additional_regions

  network = {
    name            = "hub-vpc-core"
    cidr_block      = var.hub_vpc_cidr_block
    shared_vpc_host = true
    # Observability: subnet flow logs for audit.
    flow_logs = {
      aggregation_interval = "INTERVAL_5_SEC"
      sampling             = 0.5
    }
  }

  # Opt-in Network Connectivity Center hub (the hub VPC joins as its center
  # spoke). Off = environment spokes reach the hub through VPC peering only.
  ncc = {
    enabled         = var.enable_ncc_hub
    preset_topology = var.ncc_preset_topology
    # Environment host projects join without a manual accept.
    auto_accept_projects = local.ncc_auto_accept_projects
    # Hybrid spoke for the VPN tunnels (created only when vpn.enabled too).
    vpn_site_to_site_data_transfer = var.vpn.site_to_site_data_transfer
  }

  # Opt-in hybrid connectivity: HA VPN (write-only pre-shared key) and Cloud
  # Interconnect attachments. Both off by default.
  vpn                          = local.vpn_effective
  vpn_shared_secret_wo         = var.vpn_shared_secret_wo
  vpn_shared_secret_wo_version = var.vpn_shared_secret_wo_version
  interconnects                = local.interconnects_effective

  # Opt-in central egress (Secure Web Proxy) and the data-plane alerts.
  secure_web_proxy = local.secure_web_proxy
  alerting         = var.alerting

  # Hierarchical Firewall Policy (Defense in Depth)
  hierarchical_firewall_policies = {
    "policy-hub-shared" = {
      parent       = try(local.shared_folder.name, "")
      description  = "Hub-level Defense in Depth Policy"
      associations = local.firewall_association_targets
      rules        = local.hub_firewall_rules
    }
  }

  # VPC Service Controls (Data Exfiltration Protection)
  # Only created when vpc_sc_access_policy_name is non-null. An empty map skips all
  # vpc-sc module calls, avoiding the validation error that fires when access_policy_name
  # is null but create_access_policy is false (the default).
  #
  # Set vpc_sc_enable_dry_run = true temporarily during the enforcement transition window
  # to validate that no legitimate traffic will be blocked, then switch to false (enforced).
  #
  # protected_projects: pass project NUMBERS (not IDs). The ACM API requires numeric
  # project numbers; project ID strings are silently rejected or cause misleading errors.
  vpc_service_controls = var.vpc_sc_access_policy_name != null ? {
    # Underscores, not hyphens: the vpc-sc primitive only accepts
    # ^[a-zA-Z][a-zA-Z0-9_]{0,62}$ (the former "hub-data-perimeter" key failed
    # validation, so no perimeter can exist in state under it).
    "hub_data_perimeter" = {
      organization_id    = local.org_id_normalized
      access_policy_name = var.vpc_sc_access_policy_name
      perimeter_title    = "Hub Network Data Protection Perimeter"
      description        = "Prevents data exfiltration from the hub and DNS projects"
      enable_dry_run     = var.vpc_sc_enable_dry_run

      # Hub and DNS projects only; environments have their own perimeters.
      protected_projects = local.hub_perimeter_projects
      # Base set + opt-in additions. Expanding this without the ingress
      # policy below would block the automation SA under the enforced perimeter.
      restricted_services = local.hub_base_restricted_services
      # Enforced perimeter + staged dry-run delta (null = no staged spec).
      dry_run_restricted_services = var.vpc_sc_dry_run_additional_restricted_services == null ? null : distinct(concat(local.hub_base_restricted_services, var.vpc_sc_dry_run_additional_restricted_services))

      # Opt-in ingress policy: grant the listed automation identities
      # full ingress so an enforced perimeter does not block TFC-run applies.
      # Empty identities -> no ingress policy (unchanged).
      ingress_policies = length(var.vpc_sc_ingress_identities) == 0 ? [] : [{
        identity_type = null
        identities    = var.vpc_sc_ingress_identities
        sources       = [{ access_level = "*", resource = null }]
        resources     = ["*"]
        operations    = [{ service_name = "*", method_selectors = [{ method = "*", permission = null }] }]
      }]
    }
  } : {}
}

# Peering quota guard. The PEERINGS_PER_NETWORK quota caps the peerings of one
# VPC network (25 by default; https://docs.cloud.google.com/vpc/docs/quota).
# The hub VPC also carries its Private Service Access connection, which is a
# VPC Network Peering connection to the service producer network
# (https://docs.cloud.google.com/vpc/docs/configure-private-services-access),
# so the default limit is 24 environments. Fail the plan, not the apply.
resource "terraform_data" "hub_peering_limit" {
  input = length(var.spoke_peerings)

  lifecycle {
    precondition {
      condition     = length(var.spoke_peerings) <= var.hub_peering_limit
      error_message = "${length(var.spoke_peerings)} environment peerings exceed hub_peering_limit (${var.hub_peering_limit}). Move environments to NCC (gcp.network.connectivity: ncc, docs/runbooks/gcp-peering-to-ncc-migration.md) or raise the peering quota first."
    }
  }
}

# Hub side of each environment's VPC peering. The hub owns its half: each
# gcp-workload-<env> root creates only the spoke side, so no workload state
# holds a resource in the hub project and the workload apply SA needs no right
# there. Names are unique per environment (a VPC's peering names must be
# unique). The caller passes only spokes whose network already exists: GCP
# rejects a peering to a network that does not exist yet.
resource "google_compute_network_peering" "hub_to_spoke" {
  for_each = var.spoke_peerings

  name         = "hub-to-${each.key}"
  network      = module.hub.network_self_link
  peer_network = each.value.network_self_link

  export_custom_routes = each.value.export_custom_routes
  import_custom_routes = each.value.import_custom_routes
}

# Hub Cloud Armor policy. stages/host created this project-level WAF policy
# for the hub by default (enable_cloud_armor defaulted to true); it is kept as
# a standalone primitive so the decomposition onto net-hub destroys nothing.
# It is not attached to any backend; remove it deliberately (FinOps review)
# rather than as a side effect of the refactor.
module "hub_cloud_armor" {
  source = "../../network/cloud-armor"

  project_id                 = var.hub_project_id
  policy_name                = "${var.project_prefix}-security-policy"
  description                = "WAF security policy for ${var.project_prefix}"
  enable_owasp_rules         = true
  enable_adaptive_protection = true
  enable_log4j_protection    = true
  owasp_sensitivity          = 2
  custom_rules               = {}
}

# DNS hub (name resolution): dns-anchor composition on the 'dns-hub' project.
# A workload-free VPC anchoring the organization's root private zone. The zone
# is also bound to the hub VPC, which each spoke's DNS peering zone targets.
# Formerly module.dns_hub_network (stages/host) plus module.dns_hub_zone; see
# moved.tf.
module "dns_anchor" {
  source = "../dns-anchor"

  project_id          = var.dns_project_id
  region              = var.default_region
  deletion_protection = var.enable_deletion_protection

  network = {
    name       = "dns-vpc-core"
    cidr_block = var.dns_hub_vpc_cidr_block
  }

  dns_zones = {
    "internal-root" = {
      dns_name       = "${var.internal_domain}."
      description    = "Root Internal Zone for Organization"
      dnssec_enabled = true
      # Each spoke peering zone (gcp-workload-<env> internal-peering) targets
      # the hub VPC, and a peering zone answers from the zones bound to its
      # target network. The hub VPC must therefore see this zone, or every
      # spoke lookup returns NXDOMAIN (ARC-2). The anchor VPC stays bound.
      # Adding a network updates the zone in place.
      additional_visibility_networks = [module.hub.network_self_link]
    }
  }
}

# Inbound DNS on the hub VPC, the network the VPN and Interconnects land in.
# Cloud DNS takes an entry-point address from every hub subnet; on-premises
# resolvers forward the internal domain to them, and the hub VPC sees the
# internal-root zone (dns_anchor above). Entry points are not reachable across
# VPC peering, so the policy belongs on the hub, not on the anchor VPC
# (https://docs.cloud.google.com/dns/docs/server-policies-overview). A VPC takes
# one DNS server policy, and nothing else attaches one to the hub VPC.
resource "google_dns_policy" "hub_inbound" {
  count = local.hybrid_enabled && var.hybrid_dns.enable_inbound_forwarding ? 1 : 0

  project                   = var.hub_project_id
  name                      = "${var.project_prefix}-hub-inbound"
  description               = "Inbound forwarding for on-premises resolvers (hybrid DNS)."
  enable_inbound_forwarding = true
  enable_logging            = true

  networks {
    network_url = module.hub.network_self_link
  }
}

# On-premises domains, forwarded from the hub VPC to the on-premises
# resolvers over the VPN/Interconnect (private path). Their names may not
# overlap the internal zone (variable validation); a parent domain of it is
# fine, since Cloud DNS answers from the longest matching suffix. Query
# logging comes from the DNS policy above (zone logging is public zones only).
module "hybrid_forward_zones" {
  source   = "../../network/dns"
  for_each = local.hybrid_enabled ? var.hybrid_dns.forward_zones : {}

  project_id                  = var.hub_project_id
  zone_name                   = "fwd-${each.key}"
  dns_name                    = each.value.dns_name
  description                 = "Forward ${each.value.dns_name} to on-premises resolvers."
  visibility                  = "private"
  private_visibility_networks = [module.hub.network_self_link]
  forwarding_targets          = each.value.target_ips
  forwarding_path             = "private"
}

# Hierarchical rules are evaluated before VPC rules, and a match stops
# evaluation. The IAP range therefore gets goto_next ahead of the internet deny,
# so IAP TCP forwarding reaches the tiered-vpc IAP rule, which decides it.
locals {
  hub_firewall_rules = [
    {
      priority    = 400
      action      = "goto_next"
      direction   = "INGRESS"
      description = "Hand IAP TCP forwarding (SSH/RDP) to the VPC firewall"
      layer4_configs = [
        { ip_protocol = "tcp", ports = ["22", "3389"] }
      ]
      src_ip_ranges = ["35.235.240.0/20"]
    },
    {
      priority    = 500
      action      = "deny"
      direction   = "INGRESS"
      description = "Deny RDP/SSH from Public Internet (Use IAP instead)"
      layer4_configs = [
        { ip_protocol = "tcp", ports = ["22", "3389"] }
      ]
      src_ip_ranges = ["0.0.0.0/0"]
    }
  ]
}
