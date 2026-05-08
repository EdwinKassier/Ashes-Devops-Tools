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
}

# Hub Network Actuation (The "Pipes")
module "hub_network" {
  source = "../../host"

  # Target the 'net-hub' project created in the 'shared' environment
  project_id     = var.hub_project_id
  project_prefix = var.project_prefix
  region         = var.default_region

  # Enable Networking & Shared VPC Host
  enable_networking          = true
  enable_shared_vpc_host     = true
  enable_deletion_protection = var.enable_deletion_protection
  vpc_name                   = "hub-vpc-core"
  vpc_cidr_block             = var.hub_vpc_cidr_block

  # Observability: Enable Flow Logs for Audit
  log_config_flow_sampling        = 0.5
  log_config_aggregation_interval = "INTERVAL_5_SEC"



  # Hierarchical Firewall Policy (Defense in Depth)
  hierarchical_firewall_policies = {
    "policy-hub-shared" = {
      parent      = try(local.shared_folder.name, "")
      description = "Hub-level Defense in Depth Policy"
      associations = [
        try(local.shared_folder.name, "")
      ]
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
  # Set vpc_sc_enable_dry_run = true temporarily during the enforcement transition window
  # to validate that no legitimate traffic will be blocked, then switch to false (enforced).
  vpc_service_controls = {
    "hub-data-perimeter" = {
      organization_id    = local.org_id_normalized
      access_policy_name = var.vpc_sc_access_policy_name
      perimeter_title    = "Hub Network Data Protection Perimeter"
      description        = "Prevents data exfiltration from hub-managed projects"
      enable_dry_run     = var.vpc_sc_enable_dry_run

      protected_projects = values(var.spoke_project_ids)
      restricted_services = [
        "storage.googleapis.com",
        "bigquery.googleapis.com",
        "cloudfunctions.googleapis.com",
        "run.googleapis.com"
      ]
    }
  }
}


# DNS Hub (Name Resolution)
module "dns_hub_network" {
  source = "../../host"

  # Target the 'dns-hub' project created in the 'shared' environment
  project_id     = var.dns_project_id
  project_prefix = var.project_prefix
  region         = var.default_region

  # Just a simple VPC to anchor the private zone
  enable_networking          = true
  enable_shared_vpc_host     = false
  enable_deletion_protection = var.enable_deletion_protection
  vpc_name                   = "dns-vpc-core"
  vpc_cidr_block             = var.dns_hub_vpc_cidr_block
}

module "dns_hub_zone" {
  source = "../../network/dns"

  project_id = var.dns_project_id
  zone_name  = "internal-root"
  dns_name   = "${var.internal_domain}."
  visibility = "private"

  description = "Root Internal Zone for Organization"

  # Bind to the DNS Hub's own VPC (required for private zones)
  private_visibility_networks = [
    module.dns_hub_network.network_self_link
  ]

  enable_logging = true
  dnssec_enabled = true

  depends_on = [module.dns_hub_network]
}
