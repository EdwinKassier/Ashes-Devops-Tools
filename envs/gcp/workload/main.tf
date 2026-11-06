# Upstream stage contracts (FAST-style "stage contract override"). Each one comes
# from, in order: the <layer>_contract variable, gcp.contracts.<layer> in
# config/landing-zone.yaml, then the upstream workspace's terraform_remote_state.
# A remote-state read happens ONLY when no contract was supplied (count = 0
# otherwise), so this root can plan without the upstream workspaces existing:
#   - organization → org_id, billing_account, admin_project_number
#   - projects     → environment_config[<env>] (host project, folder, region, ...)
#   - network_hub  → hub_network {vpc_self_link, dns_domain}. OPTIONAL: with
#     enable_network_hub = false there is no hub peering and no DNS peering zone
#     (local.hub_vpc_peerings / local.hub_dns_zones are empty).
# Consumers (incl. the host module block) must use the locals below, never
# data.terraform_remote_state.* directly: the data sources are count-gated.
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

# The projects and network-hub stages were split into their own roots,
# so environment_config comes from gcp-projects and hub_network from
# gcp-network-hub. org_id / billing_account / admin_project_number come from
# gcp-organization above.
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
  org_id               = local.read_organization ? data.terraform_remote_state.organization[0].outputs.org_id : local.organization_contract.org_id
  billing_account      = local.read_organization ? data.terraform_remote_state.organization[0].outputs.billing_account : local.organization_contract.billing_account
  admin_project_number = local.read_organization ? data.terraform_remote_state.organization[0].outputs.admin_project_number : local.organization_contract.admin_project_number

  # Hub network contract, or null when the network hub is not part of this
  # landing zone (enable_network_hub = false).
  hub_network = (
    !var.enable_network_hub ? null :
    local.read_network_hub ? data.terraform_remote_state.network_hub[0].outputs.hub_network : local.network_hub_contract
  )

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
}

locals {
  env_config = (
    local.read_projects
    ? data.terraform_remote_state.projects[0].outputs.environment_config[var.environment]
    : local.projects_contract.environment_config[var.environment]
  )

  labels = merge(
    {
      environment = var.environment
      managed-by  = "terraform"
    },
    local.env_config.labels,
    var.extra_labels
  )

  default_vpc_sc_ingress_policies = [
    {
      identity_type = "ANY_IDENTITY"
      identities    = null
      sources = [
        {
          access_level = null
          resource     = "//iam.googleapis.com/projects/${local.admin_project_number}/locations/global/workloadIdentityPools/*"
        }
      ]
      resources = null
      operations = [
        {
          service_name     = "storage.googleapis.com"
          method_selectors = null
        },
        {
          service_name     = "bigquery.googleapis.com"
          method_selectors = null
        },
        {
          service_name     = "container.googleapis.com"
          method_selectors = null
        }
      ]
    }
  ]

  default_vpc_sc_egress_policies = [
    {
      identity_type = "ANY_IDENTITY"
      identities    = null
      resources     = ["*"]
      operations = [
        {
          service_name     = "storage.googleapis.com"
          method_selectors = null
        }
      ]
    }
  ]

  # Access policy for the environment perimeter: an explicit
  # vpc_sc_access_policy_name (legacy org-wide policy) wins; otherwise the
  # environment's own folder-scoped policy from gcp-projects environment_config,
  # on which only this environment's workload SAs hold policyEditor.
  vpc_sc_access_policy = var.vpc_sc_access_policy_name != null ? var.vpc_sc_access_policy_name : try(local.env_config.vpc_sc_access_policy_id, null)

  # Explicit production marker from gcp-projects environment_config. The name
  # match is only a fallback for an environment_config that predates it.
  is_production = coalesce(try(local.env_config.is_production, null), can(regex("prod", lower(var.environment))))

  # Effective VPC-SC policies: caller-supplied values override the defaults above.
  effective_vpc_sc_ingress_policies = length(var.vpc_sc_ingress_policies) > 0 ? var.vpc_sc_ingress_policies : tolist(local.default_vpc_sc_ingress_policies)
  effective_vpc_sc_egress_policies  = length(var.vpc_sc_egress_policies) > 0 ? var.vpc_sc_egress_policies : tolist(local.default_vpc_sc_egress_policies)
}

data "google_project" "host_project" {
  project_id = local.env_config.host_project_id
}

# Stage contracts: the remote states above are count-gated, so module "host"
# consumes local.hub_vpc_peerings / local.hub_dns_zones / local.org_id only.
# Environment spoke network: the net-spoke composition (formerly the
# deprecated stages/host god-module). The module label stays "host" so every
# module.host.* reference, output and test keeps working; moved.tf migrates the
# network-core addresses that changed shape (module.host.module.network.*).
module "host" {
  source = "../../../modules/gcp/stages/net-spoke"

  project_id          = local.env_config.host_project_id
  project_prefix      = local.project_prefix
  region              = local.env_config.region
  deletion_protection = var.enable_deletion_protection
  labels              = local.labels

  network = {
    name            = "${local.project_prefix}-${var.environment}-vpc"
    cidr_block      = local.env_config.cidr_block
    shared_vpc_host = true
    flow_logs = {
      aggregation_interval = var.log_config_aggregation_interval
      sampling             = var.log_config_flow_sampling
    }
  }

  edge = {
    cloud_armor = {
      # Public ingress always gets the environment security policy.
      enabled             = local.enable_cloud_armor || local.enable_public_ingress
      owasp_rules         = local.enable_owasp_rules
      adaptive_protection = var.enable_adaptive_protection
      owasp_sensitivity   = var.owasp_sensitivity
    }
  }

  # Google APIs via PSC. Behind an ENFORCED perimeter the endpoint targets the
  # vpc-sc (restricted.googleapis.com) bundle, so APIs outside the perimeter's
  # supported set are unreachable from the VPC rather than an exfil path; while
  # the perimeter is absent or in dry-run, all-apis keeps everything working.
  private_service_connect = {
    target = local.psc_target
  }

  # Hub peering and the DNS peering zone (empty maps in standalone mode).
  peerings  = local.hub_vpc_peerings
  dns_zones = local.hub_dns_zones

  flow_logs_export = {
    enabled                 = true
    create_bigquery_dataset = true
    # BigQuery dataset IDs only allow alphanumerics and underscores — replace hyphens from environment name.
    bigquery_dataset_id = "vpc_flow_logs_${replace(var.environment, "-", "_")}"
    bigquery_location   = local.env_config.region
    retention_days      = var.vpc_flow_logs_retention_days
  }

  # Only created when an access policy is known (the env's scoped policy, or an
  # explicit vpc_sc_access_policy_name). Passing a perimeter with a null access
  # policy trips the vpc-sc module's validation.
  vpc_service_controls = local.vpc_sc_access_policy == null ? {} : {
    "${var.environment}_perimeter" = {
      organization_id    = "organizations/${local.org_id}"
      access_policy_name = local.vpc_sc_access_policy
      perimeter_title    = coalesce(var.vpc_sc_perimeter_title, "${upper(var.environment)} Perimeter")
      perimeter_type     = "PERIMETER_TYPE_REGULAR"
      enable_dry_run     = local.vpc_sc_enable_dry_run
      # VPC-SC requires numeric project numbers, not project IDs.
      # data.google_project.host_project is declared above and resolves the number at plan time.
      protected_projects = [
        data.google_project.host_project.number
      ]
      restricted_services = var.vpc_sc_restricted_services
      ingress_policies    = local.effective_vpc_sc_ingress_policies
      egress_policies     = local.effective_vpc_sc_egress_policies
      # Enforced status + staged dry-run delta (null = no staged spec).
      dry_run_restricted_services = var.vpc_sc_dry_run_restricted_services
    }
  }
}

module "budget" {
  count  = var.monthly_budget_limit > 0 ? 1 : 0
  source = "../../../modules/gcp/governance/billing"

  billing_account      = local.billing_account
  project_id           = local.env_config.host_project_id
  project_name         = "${local.project_prefix}-${var.environment}"
  monthly_budget_limit = var.monthly_budget_limit
  currency_code        = var.budget_currency
  region               = local.env_config.region

  projects = [
    "projects/${data.google_project.host_project.number}"
  ]

  label_filters = {
    environment = var.environment
  }

  # kms_key_name: Intentionally omitted at the app-env level. The org-level
  # budget topic is CMEK-encrypted via the CMEK key created in stages/organization.
  # App-environment budget topics use Google-managed encryption. To change this,
  # pass the CMEK key from remote state (or add it to organization_contract):
  #   kms_key_name = data.terraform_remote_state.organization[0].outputs.cmek_key_names["budget-alerts"]
  # Ensure the Pub/Sub service agent has roles/cloudkms.cryptoKeyEncrypterDecrypter first.

  labels = local.labels
}

# =============================================================================
# SERVICE TEAM REGISTRY
#
# One module instance per entry in var.service_teams. Onboarding or offboarding a
# team is a change to the service_teams map, not a hand-edited module block. The
# default empty map creates nothing, so this is backward compatible.
#
# folder_id and billing_account are normalised with trimprefix so the wiring is
# robust whether remote state exposes the bare ID or the full resource name.
# =============================================================================

module "service_team" {
  source   = "../../../modules/gcp/stages/workload"
  for_each = var.service_teams

  project_name    = each.key
  org_id          = local.org_id
  folder_id       = trimprefix(local.env_config.folder_id, "folders/")
  billing_account = trimprefix(local.billing_account, "billingAccounts/")

  activate_apis = each.value.activate_apis

  enable_shared_vpc_attachment = each.value.enable_shared_vpc_attachment
  shared_vpc_host_project_id   = local.env_config.host_project_id
  shared_vpc_subnets           = each.value.shared_vpc_subnets
  enable_gke_network_user      = each.value.enable_gke_network_user

  project_admin_group_email = each.value.project_admin_group_email
  project_admin_roles       = each.value.project_admin_roles

  labels = merge(local.labels, { team = each.key }, each.value.labels)

  # Attach service projects only after the host project is a Shared VPC host.
  depends_on = [module.host]
}

# =============================================================================
# VM BACKUP + OS PATCHING (CIS/NIST CP-9, SI-2 — BCK-05, VUL-05)
#
# Targets the env host project and every service-team project (Compute resource
# policies attach only to disks in their own project; patch deployments are
# project-scoped). Keys are static (host + team keys) so for_each is plan-safe
# even while the team projects are still being created.
#
# - enable_vm_backup_policy (default true): a snapshot-schedule resource policy
#   per project. It costs nothing until a disk is attached to it: attach it with
#   google_compute_disk_resource_policy_attachment or the disk's resource_policies.
# - enable_os_patch_management (default false): a weekly VM Manager patch
#   deployment per project, plus osconfig.googleapis.com. Off by default because
#   the workload apply SA needs roles/osconfig.patchDeploymentAdmin, which is not
#   in the default gcp-bootstrap workload_folder_roles allow-list; add it there
#   first. VMs need the OS Config agent and enable-osconfig=TRUE metadata.
# =============================================================================

locals {
  vm_ops_projects = merge(
    { host = local.env_config.host_project_id },
    { for k, _ in var.service_teams : "team-${k}" => module.service_team[k].project_id },
  )

  effective_vm_backup_schedules = var.vm_backup_schedules != null ? var.vm_backup_schedules : {
    "vm-daily-snapshots" = {}
  }

  effective_os_patch_deployments = var.os_patch_deployments != null ? var.os_patch_deployments : {
    "weekly-os-patch" = {
      description = "Weekly OS patching for ${var.environment} (Terraform-managed)."
    }
  }
}

module "vm_backup_policy" {
  source   = "../../../modules/gcp/backup/backup-plan"
  for_each = var.enable_vm_backup_policy ? local.vm_ops_projects : {}

  project_id = each.value
  region     = local.env_config.region
  labels     = local.labels
  schedules  = local.effective_vm_backup_schedules
}

resource "google_project_service" "osconfig" {
  for_each = var.enable_os_patch_management ? local.vm_ops_projects : {}

  project            = each.value
  service            = "osconfig.googleapis.com"
  disable_on_destroy = false
}

module "os_patch_management" {
  source   = "../../../modules/gcp/ops/os-config"
  for_each = var.enable_os_patch_management ? local.vm_ops_projects : {}

  project_id        = each.value
  patch_deployments = local.effective_os_patch_deployments

  depends_on = [google_project_service.osconfig]
}

# =============================================================================
# SaaS SECRET BRIDGE
#
# Opt-in. Reads the Supabase outputs from a saas-<name> workspace and writes them
# into a GCP Secret Manager secret in the host project, so a GCP runtime can use
# Supabase as a managed datastore by secret reference. Default off: no saas state
# is read and nothing is created. See docs/architecture/saas-integration.md.
# =============================================================================

data "terraform_remote_state" "saas" {
  count   = var.enable_saas_secret_bridge ? 1 : 0
  backend = "cloud"
  config = {
    organization = local.tfc_organization
    workspaces = {
      name = var.saas_workspace_name
    }
  }
}

module "saas_secret_bridge" {
  count  = var.enable_saas_secret_bridge ? 1 : 0
  source = "../../../modules/gcp/data/secret-manager"

  project_id = local.env_config.host_project_id

  secrets = {
    (var.saas_secret_name) = {
      labels = local.labels
    }
  }

  # Bridged connection details. Sensitive values are stored as a secret version,
  # so they persist in this root's state (see the variable note).
  secret_values = {
    (var.saas_secret_name) = jsonencode({
      api_url           = data.terraform_remote_state.saas[0].outputs.supabase_api_url
      service_role_key  = data.terraform_remote_state.saas[0].outputs.supabase_service_role_key
      database_password = data.terraform_remote_state.saas[0].outputs.supabase_database_password
    })
  }

  secret_accessors = {
    (var.saas_secret_name) = var.saas_secret_accessor_members
  }
}

# =============================================================================
# APPLICATION GOLDEN PATH 
#
# One module call. A service team adds an entry to var.app_services and gets, in
# the env host project: an Artifact Registry repo, a runtime SA, a Cloud Run v2
# service on the env Shared VPC (Direct VPC egress), optional private Cloud SQL,
# and an optional GitHub deploy identity on an app-only WIF pool. The default
# (app_services = {}, every flag off) creates nothing. Guide:
# docs/guides/deploying-a-service.md.
# =============================================================================

module "app_services" {
  source = "../../../modules/gcp/stages/app-services"

  project_id     = local.env_config.host_project_id
  project_number = local.env_config.host_project_number
  region         = local.env_config.region
  environment    = var.environment
  labels         = local.labels

  # The env VPC (not the hub): the host stage creates Private Service Access on
  # it by default, which private-IP Cloud SQL requires.
  network_id = module.host.network_id
  # Default Cloud Run / GKE subnet: the first private (compute-tier) subnet.
  subnetwork_id = var.app_subnetwork_id != null ? var.app_subnetwork_id : try(values(module.host.subnets.private)[0].id, null)

  services                       = local.app_services
  bootstrap_image                = local.app_bootstrap_image
  enable_deletion_protection     = var.enable_deletion_protection
  artifact_registry_kms_key_name = var.artifact_registry_kms_key_name
  enable_vulnerability_scanning  = var.enable_artifact_registry_vulnerability_scanning

  enable_app_deploy_wif      = var.enable_app_deploy_wif
  app_deploy_wif_pool_id     = var.app_deploy_wif_pool_id
  github_repository_owner_id = var.github_repository_owner_id

  enable_gke_autopilot              = var.enable_gke_autopilot
  gke_master_ipv4_cidr_block        = var.gke_master_ipv4_cidr_block
  gke_master_authorized_networks    = var.gke_master_authorized_networks
  gke_cluster_secondary_range_name  = var.gke_cluster_secondary_range_name
  gke_services_secondary_range_name = var.gke_services_secondary_range_name

  # PSA (for Cloud SQL), subnets and the bridged SaaS secret must exist first.
  depends_on = [module.host, module.saas_secret_bridge]
}

# =============================================================================
# PUBLIC INGRESS (opt-in) — one global external Application Load Balancer per
# exposed app service: reserved anycast IP, serverless NEG -> Cloud Run, backend
# with the environment Cloud Armor policy, Google-managed certificate for the
# service's domains, HTTPS proxy and an HTTP->HTTPS redirect. The Cloud Run
# service is switched to INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER so the run.app
# URL is not a bypass. Unauthenticated invocation disables the Cloud Run Invoker
# IAM check (invoker_iam_disabled) rather than binding allUsers, so it works
# under domain-restricted sharing; exposure is bounded to the ALB + Cloud Armor
# by ingress, the app-services validation and the org run.allowedIngress policy.
# =============================================================================

locals {
  public_ingress_services = var.public_ingress_services != null ? var.public_ingress_services : try(local.cfg.public_ingress[var.environment], {})
  enable_public_ingress   = var.enable_public_ingress != null ? var.enable_public_ingress : length(local.public_ingress_services) > 0
  public_ingress          = local.enable_public_ingress ? local.public_ingress_services : {}

  # Exposed services default to LB-only ingress + public invocation; the rest
  # keep the stage defaults (internal only, authenticated). An explicit value in
  # the app_services entry always wins.
  app_services = {
    for k, s in var.app_services : k => merge({
      ingress                = contains(keys(local.public_ingress), k) ? "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER" : "INGRESS_TRAFFIC_INTERNAL_ONLY"
      enable_unauthenticated = contains(keys(local.public_ingress), k)
    }, s)
  }

  app_bootstrap_image = coalesce(var.app_bootstrap_image, local.cfg.app_bootstrap_image, "us-docker.pkg.dev/cloudrun/container/hello")
}

module "app_ingress" {
  source   = "../../../modules/gcp/network/app-ingress"
  for_each = local.public_ingress

  project_id             = local.env_config.host_project_id
  region                 = local.env_config.region
  name                   = "${var.environment}-${each.key}"
  domains                = each.value.domains
  cloud_run_service_name = module.app_services.services[each.key].service_name
  security_policy_id     = module.host.security_policy_self_link
  enable_cdn             = each.value.enable_cdn
  dns_managed_zone       = each.value.dns_managed_zone
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

locals {
  psc_target = coalesce(var.private_service_connect_target, local.vpc_sc_access_policy != null && !local.vpc_sc_enable_dry_run ? "vpc-sc" : "all-apis")
}
