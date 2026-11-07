# Upstream stage contracts (FAST-style "stage contract override"): the
# <layer>_contract variable, else gcp.contracts.<layer> in config/landing-zone.yaml,
# else the upstream workspace's remote state (read ONLY when no contract was given):
#   - organization → org_id, billing_account, admin_project_number
#   - projects     → environment_config[<env>] (host project, folder, region, ...)
#   - network_hub  → hub_network {vpc_self_link, dns_domain, optional ncc_hub_id /
#     ncc_spoke_group}. OPTIONAL: enable_network_hub = false means no hub peering
#     and no DNS peering zone.
# Use the locals below, never data.terraform_remote_state.* (they are count-gated).
locals {
  organization_contract = var.organization_contract != null ? var.organization_contract : local.cfg.organization_contract
  projects_contract     = var.projects_contract != null ? var.projects_contract : local.cfg.projects_contract
  network_hub_contract  = var.network_hub_contract != null ? var.network_hub_contract : local.cfg.network_hub_contract

  read_organization = local.organization_contract == null
  read_projects     = local.projects_contract == null
  read_network_hub  = var.enable_network_hub && local.network_hub_contract == null
}

data "terraform_remote_state" "organization" {
  count   = local.read_organization ? 1 : 0
  backend = "cloud"
  config = {
    organization = local.tfc_organization
    workspaces = {
      name = var.organization_workspace_name
    }
  }
}

data "terraform_remote_state" "projects" {
  count   = local.read_projects ? 1 : 0
  backend = "cloud"
  config = {
    organization = local.tfc_organization
    workspaces = {
      name = var.projects_workspace_name
    }
  }
}

data "terraform_remote_state" "network_hub" {
  count   = local.read_network_hub ? 1 : 0
  backend = "cloud"
  config = {
    organization = local.tfc_organization
    workspaces = {
      name = var.network_hub_workspace_name
    }
  }
}

locals {
  # Each upstream is read through its single `contract` output. A producer
  # state from before that output existed (N-1, not yet re-applied) exposes the
  # same keys as individual outputs, so the read falls back to them; that
  # fallback goes at v1.0 with the individual outputs (UPGRADING.md).
  org_remote         = local.read_organization ? try(data.terraform_remote_state.organization[0].outputs.contract, data.terraform_remote_state.organization[0].outputs) : null
  projects_remote    = local.read_projects ? try(data.terraform_remote_state.projects[0].outputs.contract, data.terraform_remote_state.projects[0].outputs) : null
  network_hub_remote = local.read_network_hub ? try(data.terraform_remote_state.network_hub[0].outputs.contract, data.terraform_remote_state.network_hub[0].outputs) : null

  org_id               = local.read_organization ? local.org_remote.org_id : local.organization_contract.org_id
  billing_account      = local.read_organization ? local.org_remote.billing_account : local.organization_contract.billing_account
  admin_project_number = local.read_organization ? local.org_remote.admin_project_number : local.organization_contract.admin_project_number

  # Hub network contract, or null when the network hub is not part of this
  # landing zone (enable_network_hub = false).
  hub_network = (
    !var.enable_network_hub ? null :
    local.read_network_hub ? local.network_hub_remote.hub_network : local.network_hub_contract
  )

  # Hub connectivity: peering (default) or an NCC spoke on the hub's NCC hub.
  # Standalone (no hub) stays peering with an empty peerings map.
  network_connectivity = local.hub_network == null ? "peering" : coalesce(
    var.network_connectivity,
    try(local.cfg.environment_connectivity[var.environment], null),
    local.cfg.network_connectivity,
    "peering",
  )
  hub_ncc = {
    hub_id = try(local.hub_network.ncc_hub_id, null)
    group  = coalesce(try(local.hub_network.ncc_spoke_group, null), "edge")
  }

  # Hub-dependent host inputs: empty maps in standalone mode (no hub peering, no
  # DNS peering zone). Built with a filtered for-expression so both modes share
  # one map type.
  hub_vpc_peerings = {
    for k, v in {
      "hub-peering" = {
        peer_network         = try(local.hub_network.vpc_self_link, null)
        export_custom_routes = true
        import_custom_routes = true
      }
    } : k => v if local.hub_network != null
  }
  hub_dns_zones = {
    for k, v in {
      "internal-peering" = {
        dns_name        = try(local.hub_network.dns_domain, null)
        visibility      = "private"
        description     = "Peering zone to resolve internal hub DNS"
        peering_network = try(local.hub_network.vpc_self_link, null)
        dnssec_enabled  = true
      }
    } : k => v if local.hub_network != null
  }

  # A missing environment resolves to a well-formed placeholder (provider-side
  # validation still runs at plan) so that terraform_data.projects_contract_guard,
  # not a bare lookup error, fails the plan. It can never be applied.
  env_config_map = local.read_projects ? local.projects_remote.environment_config : local.projects_contract.environment_config
  env_config = try(local.env_config_map[var.environment], {
    folder_id               = "folders/0"
    host_project_id         = "contract-missing-env"
    host_project_number     = "0"
    region                  = "us-central1"
    cidr_block              = "10.255.0.0/24"
    labels                  = {}
    is_production           = null
    vpc_sc_access_policy_id = null
  })

  labels = merge({ environment = var.environment, managed-by = "terraform" }, local.env_config.labels, var.extra_labels)

  # Access policy for the environment perimeter: an explicit
  # vpc_sc_access_policy_name (legacy org-wide policy) wins; otherwise the
  # environment's own folder-scoped policy from gcp-projects environment_config,
  # on which only this environment's workload SAs hold policyEditor.
  vpc_sc_access_policy = var.vpc_sc_access_policy_name != null ? var.vpc_sc_access_policy_name : try(local.env_config.vpc_sc_access_policy_id, null)

  # Explicit production marker from gcp-projects environment_config. The name
  # match is only a fallback for an environment_config that predates it.
  is_production = coalesce(try(local.env_config.is_production, null), can(regex("prod", lower(var.environment))))

  # Public ingress: var.public_ingress_services, else
  # gcp.workload.public_ingress.<env>. Exposure needs the Cloud Armor policy.
  public_ingress_services = var.public_ingress_services != null ? var.public_ingress_services : try(local.cfg.public_ingress[var.environment], {})
  enable_public_ingress   = var.enable_public_ingress != null ? var.enable_public_ingress : length(local.public_ingress_services) > 0
  public_ingress          = local.enable_public_ingress ? local.public_ingress_services : {}

  app_bootstrap_image = coalesce(var.app_bootstrap_image, local.cfg.app_bootstrap_image, "us-docker.pkg.dev/cloudrun/container/hello")
}

# SaaS secret bridge (opt-in, default off: no saas outputs are read). The
# Supabase outputs of a saas-<name> workspace; the environment stage writes them
# into a Secret Manager secret. See docs/architecture/saas-integration.md.
#
# The read is ephemeral and the stage writes the value with the write-only
# secret_data_wo, so the values are in neither this root's plan nor its state.
# Authenticated with the saas-outputs-reader team token (TFE_TOKEN on the
# bridging workspaces, docs/runbooks/saas-bootstrap.md).

ephemeral "tfe_outputs" "saas" {
  count        = var.enable_saas_secret_bridge ? 1 : 0
  organization = local.tfc_organization
  workspace    = var.saas_workspace_name

  lifecycle {
    # The write-only version is non-ephemeral, so it comes from the config file
    # (saas.bridge_rotation), not from this read. Refuse to push while the saas
    # workspace has not yet published the same counter: pushing then would write
    # the old values under the new version, and nothing would re-push them.
    postcondition {
      condition     = try(tonumber(self.nonsensitive_values.bridge_version), 1) == local.saas_bridge_version
      error_message = "saas bridge_version (published by ${coalesce(var.saas_workspace_name, "the saas workspace")}) differs from this workload's saas_bridge_version / saas.bridge_rotation. Apply the saas workspace first, then re-run this workload."
    }
  }
}

# The environment (modules/gcp/stages/environment): spoke network + perimeter,
# budget, service teams, VM backup / OS patching, the SaaS secret bridge, app
# services and public ingress. This root resolves config and contracts; the stage
# composes. moved.tf moves the state of the former inline composition.

module "environment" {
  source = "../../../modules/gcp/stages/environment"

  environment          = var.environment
  project_prefix       = local.project_prefix
  org_id               = local.org_id
  billing_account      = local.billing_account
  admin_project_number = local.admin_project_number
  labels               = local.labels
  deletion_protection  = var.enable_deletion_protection

  host_project = {
    project_id     = local.env_config.host_project_id
    project_number = local.env_config.host_project_number
    folder_id      = local.env_config.folder_id
    region         = local.env_config.region
    cidr_block     = local.env_config.cidr_block
  }

  network = {
    flow_logs = {
      aggregation_interval = var.log_config_aggregation_interval
      sampling             = var.log_config_flow_sampling
    }
    flow_logs_retention_days       = var.vpc_flow_logs_retention_days
    private_service_connect_target = var.private_service_connect_target
    additional_regions             = local.additional_regions
  }

  hub = {
    connectivity = local.network_connectivity
    ncc          = local.hub_ncc
    peerings     = local.hub_vpc_peerings
    dns_zones    = local.hub_dns_zones
  }

  cloud_armor = {
    # Public ingress always gets the environment security policy.
    enabled             = local.enable_cloud_armor || local.enable_public_ingress
    owasp_rules         = local.enable_owasp_rules
    adaptive_protection = var.enable_adaptive_protection
    owasp_sensitivity   = var.owasp_sensitivity
  }

  vpc_service_controls = {
    access_policy_name          = local.vpc_sc_access_policy
    perimeter_title             = var.vpc_sc_perimeter_title
    enable_dry_run              = local.vpc_sc_enable_dry_run
    restricted_services         = var.vpc_sc_restricted_services
    dry_run_restricted_services = var.vpc_sc_dry_run_restricted_services
    ingress_policies            = var.vpc_sc_ingress_policies
    egress_policies             = var.vpc_sc_egress_policies
  }

  budget = {
    monthly_limit = var.monthly_budget_limit
    currency      = var.budget_currency
  }

  service_teams = local.service_teams

  vm_operations = {
    enable_backup_policy       = var.enable_vm_backup_policy
    backup_schedules           = var.vm_backup_schedules
    enable_os_patch_management = var.enable_os_patch_management
    os_patch_deployments       = var.os_patch_deployments
  }

  saas_secret_bridge = {
    enabled          = var.enable_saas_secret_bridge
    secret_name      = var.saas_secret_name
    accessor_members = var.saas_secret_accessor_members
    value_version    = local.saas_bridge_version
  }
  # Written write-only; still stored in this state via the remote-state read
  # (docs/known-gaps.md).
  saas_secret_bridge_value = var.enable_saas_secret_bridge ? jsonencode({
    api_url           = ephemeral.tfe_outputs.saas[0].values.supabase_api_url
    service_role_key  = ephemeral.tfe_outputs.saas[0].values.supabase_service_role_key
    database_password = ephemeral.tfe_outputs.saas[0].values.supabase_database_password
  }) : null

  app_services   = local.app_services_input
  public_ingress = local.public_ingress
  app_platform = {
    subnetwork_id                  = var.app_subnetwork_id
    bootstrap_image                = local.app_bootstrap_image
    artifact_registry_kms_key_name = var.artifact_registry_kms_key_name
    enable_vulnerability_scanning  = var.enable_artifact_registry_vulnerability_scanning
    enable_deploy_wif              = var.enable_app_deploy_wif
    deploy_wif_pool_id             = var.app_deploy_wif_pool_id
    github_repository_owner_id     = var.github_repository_owner_id
    enable_alerts                  = var.enable_app_alerts
    alert_notification_channel_ids = var.app_alert_notification_channel_ids
    gke = {
      enabled                       = var.enable_gke_autopilot
      master_ipv4_cidr_block        = var.gke_master_ipv4_cidr_block
      master_authorized_networks    = var.gke_master_authorized_networks
      cluster_secondary_range_name  = var.gke_cluster_secondary_range_name
      services_secondary_range_name = var.gke_services_secondary_range_name
    }
  }
}

# Nothing else ties production to an enforced perimeter. Warn (check blocks never
# fail the plan) when a production environment (environment_config is_production)
# has no perimeter or only a dry-run one.
check "vpc_sc_enforced_in_prod" {
  assert {
    condition     = !local.is_production || (local.vpc_sc_access_policy != null && !local.vpc_sc_enable_dry_run)
    error_message = "Environment '${var.environment}' is production but its VPC-SC perimeter is ${local.vpc_sc_access_policy == null ? "NOT CREATED (no scoped access policy in environment_config and vpc_sc_access_policy_name is null)" : "in DRY-RUN (vpc_sc_enable_dry_run = true)"}. Dry-run gives no exfiltration protection: validate the violation logs, then set vpc_sc_enable_dry_run = false (use vpc_sc_dry_run_restricted_services to keep staging further changes)."
  }
}

# Fail early, naming the contract field, when the effective gcp-projects contract
# (variable, config file or the upstream workspace's contract output) lacks a
# key this root reads. The reads above tolerate the gap so that this
# precondition, not a bare "key not in collection", is the plan error.
resource "terraform_data" "projects_contract_guard" {
  lifecycle {
    precondition {
      condition     = contains(keys(local.env_config_map), var.environment)
      error_message = "The gcp-projects contract environment_config has no \"${var.environment}\" entry (projects_contract / gcp.contracts.projects, else the ${var.projects_workspace_name} workspace's contract output); add the environment to gcp.environments and apply gcp-projects first."
    }
  }
}
