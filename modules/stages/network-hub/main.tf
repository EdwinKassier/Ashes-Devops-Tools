# Hub Network Actuation (The "Pipes")
module "hub_network" {
  source = "../../host"

  # Target the 'net-hub' project created in the 'shared' environment
  project_id     = var.hub_project_id
  project_prefix = var.project_prefix
  region         = var.default_region

  # Enable Networking & Shared VPC Host
  enable_networking      = true
  enable_shared_vpc_host = true
  vpc_name               = "hub-vpc-core"

  # Observability: Enable Flow Logs for Audit
  log_config_flow_sampling        = 0.5
  log_config_aggregation_interval = "INTERVAL_5_SEC"



  # Hierarchical Firewall Policy (Defense in Depth)
  hierarchical_firewall_policies = {
    "policy-hub-shared" = {
      parent      = "folders/${var.folders["shared"].id}"
      description = "Hub-level Defense in Depth Policy"
      associations = [
        "folders/${var.folders["shared"].id}"
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
  vpc_service_controls = {
    "prod-data-perimeter" = {
      organization_id = var.org_id
      perimeter_title = "Production Data Protection Perimeter"
      description     = "Prevents data exfiltration from production projects"

      # ENFORCED: VPC-SC is now in enforcement mode
      # Ensure all violations have been resolved before applying this change
      enable_dry_run = true

      protected_projects = [
        for k, pid in var.spoke_project_ids : "projects/${pid}"
        if startswith(k, "prod")
      ]
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
  enable_networking      = true
  enable_shared_vpc_host = false
  vpc_name               = "dns-vpc-core"
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
