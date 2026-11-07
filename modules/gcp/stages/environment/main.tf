/**
 * Copyright 2026 Ashes
 *
 * Environment Stage - one application environment, composed.
 *
 * The composition behind every gcp-workload-<env> workspace: the spoke network
 * (net-spoke, with the environment VPC-SC perimeter), the budget, the service
 * team registry (stages/workload), VM backup and OS patching, the SaaS secret
 * bridge, the application golden path (stages/app-services) and public ingress
 * (network/app-ingress). The caller resolves config and upstream contracts and
 * passes plain values; this module reads no remote state.
 */

locals {
  default_vpc_sc_ingress_policies = [
    {
      identity_type = "ANY_IDENTITY"
      identities    = null
      sources = [
        {
          access_level = null
          resource     = "//iam.googleapis.com/projects/${var.admin_project_number}/locations/global/workloadIdentityPools/*"
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

  vpc_sc = var.vpc_service_controls

  # Effective VPC-SC policies: caller-supplied values override the defaults above.
  effective_vpc_sc_ingress_policies = length(local.vpc_sc.ingress_policies) > 0 ? local.vpc_sc.ingress_policies : tolist(local.default_vpc_sc_ingress_policies)
  effective_vpc_sc_egress_policies  = length(local.vpc_sc.egress_policies) > 0 ? local.vpc_sc.egress_policies : tolist(local.default_vpc_sc_egress_policies)

  # Google APIs via PSC. Behind an ENFORCED perimeter the endpoint targets the
  # vpc-sc (restricted.googleapis.com) bundle, so APIs outside the perimeter's
  # supported set are unreachable from the VPC rather than an exfil path; while
  # the perimeter is absent or in dry-run, all-apis keeps everything working.
  psc_target = coalesce(var.network.private_service_connect_target, local.vpc_sc.access_policy_name != null && !local.vpc_sc.enable_dry_run ? "vpc-sc" : "all-apis")
}

data "google_project" "host_project" {
  project_id = var.host_project.project_id
}

# Environment spoke network: the net-spoke composition. The label stays "host"
# so the caller's moved blocks (and the network-core moves recorded in
# envs/gcp/workload/moved.tf) keep their addresses.
module "host" {
  source = "../net-spoke"

  project_id          = var.host_project.project_id
  project_prefix      = var.project_prefix
  region              = var.host_project.region
  deletion_protection = var.deletion_protection
  labels              = var.labels

  network = {
    name            = "${var.project_prefix}-${var.environment}-vpc"
    cidr_block      = var.host_project.cidr_block
    shared_vpc_host = true
    flow_logs = {
      aggregation_interval = var.network.flow_logs.aggregation_interval
      sampling             = var.network.flow_logs.sampling
    }
  }

  edge = {
    cloud_armor = {
      enabled             = var.cloud_armor.enabled
      owasp_rules         = var.cloud_armor.owasp_rules
      adaptive_protection = var.cloud_armor.adaptive_protection
      owasp_sensitivity   = var.cloud_armor.owasp_sensitivity
    }
  }

  private_service_connect = {
    target = local.psc_target
  }

  # Hub peering (or, with connectivity = ncc, an NCC spoke on the hub's NCC hub
  # instead) and the DNS peering zone (empty maps in standalone mode). DNS
  # peering is not VPC peering, so the zone stays in both modes.
  connectivity = var.hub.connectivity
  ncc          = var.hub.ncc
  peerings     = var.hub.peerings
  dns_zones    = var.hub.dns_zones

  flow_logs_export = {
    enabled                 = true
    create_bigquery_dataset = true
    # BigQuery dataset IDs only allow alphanumerics and underscores — replace hyphens from environment name.
    bigquery_dataset_id = "vpc_flow_logs_${replace(var.environment, "-", "_")}"
    bigquery_location   = var.host_project.region
    retention_days      = var.network.flow_logs_retention_days
  }

  # Only created when an access policy is known (the env's scoped policy, or an
  # explicit legacy policy). Passing a perimeter with a null access policy trips
  # the vpc-sc module's validation.
  vpc_service_controls = local.vpc_sc.access_policy_name == null ? {} : {
    "${var.environment}_perimeter" = {
      organization_id    = "organizations/${var.org_id}"
      access_policy_name = local.vpc_sc.access_policy_name
      perimeter_title    = coalesce(local.vpc_sc.perimeter_title, "${upper(var.environment)} Perimeter")
      perimeter_type     = "PERIMETER_TYPE_REGULAR"
      enable_dry_run     = local.vpc_sc.enable_dry_run
      # VPC-SC requires numeric project numbers, not project IDs.
      protected_projects = [
        data.google_project.host_project.number
      ]
      restricted_services = local.vpc_sc.restricted_services
      ingress_policies    = local.effective_vpc_sc_ingress_policies
      egress_policies     = local.effective_vpc_sc_egress_policies
      # Enforced status + staged dry-run delta (null = no staged spec).
      dry_run_restricted_services = local.vpc_sc.dry_run_restricted_services
    }
  }
}

module "budget" {
  count  = var.budget.monthly_limit > 0 ? 1 : 0
  source = "../../governance/billing"

  billing_account      = var.billing_account
  project_id           = var.host_project.project_id
  project_name         = "${var.project_prefix}-${var.environment}"
  monthly_budget_limit = var.budget.monthly_limit
  currency_code        = var.budget.currency
  region               = var.host_project.region

  projects = [
    "projects/${data.google_project.host_project.number}"
  ]

  label_filters = {
    environment = var.environment
  }

  # kms_key_name: Intentionally omitted at the app-env level. The org-level
  # budget topic is CMEK-encrypted via the CMEK key created in stages/organization.
  # App-environment budget topics use Google-managed encryption. To change this,
  # pass the CMEK key in from the organization contract. Ensure the Pub/Sub
  # service agent has roles/cloudkms.cryptoKeyEncrypterDecrypter first.

  labels = var.labels
}

# =============================================================================
# SERVICE TEAM REGISTRY
#
# One module instance per entry in var.service_teams. Onboarding or offboarding
# a team is a change to the map, not a hand-edited module block. The default
# empty map creates nothing.
#
# folder_id and billing_account are normalised with trimprefix so the wiring is
# robust whether the contract carries the bare ID or the full resource name.
# =============================================================================

module "service_team" {
  source   = "../workload"
  for_each = var.service_teams

  project_name    = each.key
  org_id          = var.org_id
  folder_id       = trimprefix(var.host_project.folder_id, "folders/")
  billing_account = trimprefix(var.billing_account, "billingAccounts/")

  activate_apis = distinct(concat(each.value.activate_apis, local.team_service_apis[each.key]))

  enable_shared_vpc_attachment = each.value.enable_shared_vpc_attachment
  shared_vpc_host_project_id   = var.host_project.project_id
  shared_vpc_subnets           = each.value.shared_vpc_subnets
  enable_gke_network_user      = each.value.enable_gke_network_user

  project_admin_group_email = each.value.project_admin_group_email
  project_admin_roles       = each.value.project_admin_roles

  labels = merge(var.labels, { team = each.key }, each.value.labels)

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
# - enable_backup_policy (default true): a snapshot-schedule resource policy per
#   project. It costs nothing until a disk is attached to it: attach it with
#   google_compute_disk_resource_policy_attachment or the disk's resource_policies.
# - enable_os_patch_management (default true): a weekly VM Manager patch
#   deployment per project, plus osconfig.googleapis.com. The workload apply SA
#   needs roles/osconfig.patchDeploymentAdmin (gcp-bootstrap
#   workload_folder_roles). VMs need the OS Config agent and
#   enable-osconfig=TRUE metadata.
# =============================================================================

locals {
  vm_ops_projects = merge(
    { host = var.host_project.project_id },
    { for k, _ in var.service_teams : "team-${k}" => module.service_team[k].project_id },
  )

  effective_vm_backup_schedules = var.vm_operations.backup_schedules != null ? var.vm_operations.backup_schedules : {
    "vm-daily-snapshots" = {}
  }

  effective_os_patch_deployments = var.vm_operations.os_patch_deployments != null ? var.vm_operations.os_patch_deployments : {
    "weekly-os-patch" = {
      description = "Weekly OS patching for ${var.environment} (Terraform-managed)."
    }
  }
}

module "vm_backup_policy" {
  source   = "../../backup/backup-plan"
  for_each = var.vm_operations.enable_backup_policy ? local.vm_ops_projects : {}

  project_id = each.value
  region     = var.host_project.region
  labels     = var.labels
  schedules  = local.effective_vm_backup_schedules
}

resource "google_project_service" "osconfig" {
  for_each = var.vm_operations.enable_os_patch_management ? local.vm_ops_projects : {}

  project            = each.value
  service            = "osconfig.googleapis.com"
  disable_on_destroy = false
}

module "os_patch_management" {
  source   = "../../ops/os-config"
  for_each = var.vm_operations.enable_os_patch_management ? local.vm_ops_projects : {}

  project_id        = each.value
  patch_deployments = local.effective_os_patch_deployments

  depends_on = [google_project_service.osconfig]
}

# =============================================================================
# SaaS SECRET BRIDGE
#
# Opt-in. Writes the caller-supplied connection payload (the Supabase outputs of
# a saas-<name> workspace) into a Secret Manager secret in the host project, so
# a GCP runtime can use Supabase by secret reference. The module writes it with
# the write-only secret_data_wo, so the secret version holds no plaintext in
# state. See docs/architecture/saas-integration.md.
# =============================================================================

module "saas_secret_bridge" {
  count  = var.saas_secret_bridge.enabled ? 1 : 0
  source = "../../data/secret-manager"

  project_id = var.host_project.project_id

  secrets = {
    (var.saas_secret_bridge.secret_name) = {
      labels = var.labels
    }
  }

  secret_value_versions = {
    (var.saas_secret_bridge.secret_name) = var.saas_secret_bridge.value_version
  }

  secret_values = {
    (var.saas_secret_bridge.secret_name) = var.saas_secret_bridge_value
  }

  secret_accessors = {
    (var.saas_secret_bridge.secret_name) = var.saas_secret_bridge.accessor_members
  }
}

# =============================================================================
# APPLICATION GOLDEN PATH
#
# One module call. A service team adds an entry to var.app_services and gets, in
# the env host project (or its service_team's project): an Artifact Registry
# repo, a runtime SA, a Cloud Run v2 service or job on the env Shared VPC (Direct
# VPC egress), optional private Cloud SQL, an optional SLO, and an optional
# GitHub deploy identity on an app-only WIF pool. The default (app_services =
# {}, every flag off) creates nothing. Guide: docs/guides/deploying-a-service.md.
# =============================================================================

locals {
  # Exposed services default to LB-only ingress + public invocation; the rest
  # keep the stage defaults (internal only, authenticated). An explicit value in
  # the app_services entry always wins.
  #
  # A service with `service_team = "<key>"` deploys into that team's service
  # project: its project_id / project_number come from module.service_team[<key>]
  # (try() keeps an unknown key inert here; the caller rejects it).
  # grant_network_access is set explicitly because the project id is unknown
  # until apply when the team project is created in the same run.
  app_services = {
    for k, s in var.app_services : k => merge({
      ingress                = contains(keys(var.public_ingress), k) ? "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER" : "INGRESS_TRAFFIC_INTERNAL_ONLY"
      enable_unauthenticated = contains(keys(var.public_ingress), k)
      }, s,
      { for a, v in {
        project_id           = try(module.service_team[s.service_team].project_id, null)
        project_number       = try(module.service_team[s.service_team].project_number, null)
        grant_network_access = true
        network_access_group = try(s.service_team, null)
      } : a => v if try(s.service_team, null) != null }
    )
  }

  # APIs a team project needs to host the services pointed at it (merged into
  # the team's own activate_apis). Derived from the inputs, not module outputs.
  team_service_apis = {
    for team, _ in var.service_teams : team => (
      length([for k, s in var.app_services : k if try(s.service_team, null) == team]) == 0 ? [] : distinct(concat(
        ["run.googleapis.com", "artifactregistry.googleapis.com", "iam.googleapis.com", "containerscanning.googleapis.com", "monitoring.googleapis.com"],
        anytrue([for k, s in var.app_services : try(s.database, null) != null if try(s.service_team, null) == team]) ? ["sqladmin.googleapis.com"] : [],
        anytrue([for k, s in var.app_services : length(try(s.secrets, {})) > 0 if try(s.service_team, null) == team]) ? ["secretmanager.googleapis.com"] : [],
        anytrue([for k, s in var.app_services : try(s.pubsub.enabled, false) == true if try(s.service_team, null) == team]) ? ["pubsub.googleapis.com"] : [],
      ))
    )
  }
}

module "app_services" {
  source = "../app-services"

  project_id     = var.host_project.project_id
  project_number = var.host_project.project_number
  region         = var.host_project.region
  environment    = var.environment
  labels         = var.labels

  # The env VPC (not the hub): the host stage creates Private Service Access on
  # it by default, which private-IP Cloud SQL requires.
  network_id = module.host.network_id
  # Default Cloud Run / GKE subnet: the first private (compute-tier) subnet.
  subnetwork_id = var.app_platform.subnetwork_id != null ? var.app_platform.subnetwork_id : try(values(module.host.subnets.private)[0].id, null)

  services                       = local.app_services
  bootstrap_image                = var.app_platform.bootstrap_image
  enable_deletion_protection     = var.deletion_protection
  artifact_registry_kms_key_name = var.app_platform.artifact_registry_kms_key_name
  enable_vulnerability_scanning  = var.app_platform.enable_vulnerability_scanning

  enable_app_deploy_wif      = var.app_platform.enable_deploy_wif
  app_deploy_wif_pool_id     = var.app_platform.deploy_wif_pool_id
  github_repository_owner_id = var.app_platform.github_repository_owner_id

  # Per-service Cloud Monitoring alerts (5xx ratio, p99 latency).
  enable_alerts                  = var.app_platform.enable_alerts
  alert_notification_channel_ids = var.app_platform.alert_notification_channel_ids

  enable_gke_autopilot              = var.app_platform.gke.enabled
  gke_master_ipv4_cidr_block        = var.app_platform.gke.master_ipv4_cidr_block
  gke_master_authorized_networks    = var.app_platform.gke.master_authorized_networks
  gke_cluster_secondary_range_name  = var.app_platform.gke.cluster_secondary_range_name
  gke_services_secondary_range_name = var.app_platform.gke.services_secondary_range_name

  # PSA (for Cloud SQL), subnets and the bridged SaaS secret must exist first.
  depends_on = [module.host, module.saas_secret_bridge, module.service_team]
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

module "app_ingress" {
  source   = "../../network/app-ingress"
  for_each = var.public_ingress

  project_id             = var.host_project.project_id
  region                 = var.host_project.region
  name                   = "${var.environment}-${each.key}"
  domains                = each.value.domains
  cloud_run_service_name = module.app_services.services[each.key].service_name
  security_policy_id     = module.host.security_policy_self_link
  enable_cdn             = each.value.enable_cdn
  dns_managed_zone       = each.value.dns_managed_zone
}
