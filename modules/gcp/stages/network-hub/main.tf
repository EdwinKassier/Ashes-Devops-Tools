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

  # Staged dry-run delta for the hub perimeter (see network/vpc-sc): null =
  # no staged spec; a list = enforced status keeps the base set, the dry-run
  # spec trials base set + these.
  # The NCC spoke group auto-accepts spokes from every environment host
  # project (bare numbers; empty entries dropped).
  ncc_auto_accept_projects = sort(distinct(compact([for n in values(var.spoke_project_numbers) : trimprefix(n, "projects/")])))

  hub_base_restricted_services = distinct(concat([
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "cloudfunctions.googleapis.com",
    "run.googleapis.com"
  ], var.vpc_sc_additional_restricted_services))
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
  vpn                          = var.vpn
  vpn_shared_secret_wo         = var.vpn_shared_secret_wo
  vpn_shared_secret_wo_version = var.vpn_shared_secret_wo_version
  interconnects                = var.interconnects

  # Hierarchical Firewall Policy (Defense in Depth)
  hierarchical_firewall_policies = {
    "policy-hub-shared" = {
      parent       = try(local.shared_folder.name, "")
      description  = "Hub-level Defense in Depth Policy"
      associations = local.firewall_association_targets
      rules = [
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
      description        = "Prevents data exfiltration from hub-managed projects"
      enable_dry_run     = var.vpc_sc_enable_dry_run

      # values() returns project numbers from the spoke_project_numbers map.
      protected_projects = values(var.spoke_project_numbers)
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
# A workload-free VPC anchoring the organization's root private zone; spokes
# resolve it through DNS peering. Formerly module.dns_hub_network (stages/host)
# plus module.dns_hub_zone; see moved.tf.
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
    }
  }
}
