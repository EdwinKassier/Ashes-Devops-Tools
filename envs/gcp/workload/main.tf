# This root depends on the organization root (envs/gcp/organization) via remote state.
# Trade-offs of this coupling:
#   Pro: avoids re-declaring org-level outputs (billing account, folder IDs, hub network).
#   Con: envs/gcp/workload cannot be planned or applied in isolation — the organization workspace
#        must exist and its outputs must be populated first.
# If you are onboarding a new environment, run envs/gcp/organization first.
# If you need to work offline, override outputs with a stub backend using a local tfvars file.
data "terraform_remote_state" "organization" {
  backend = "cloud"
  config = {
    organization = var.tfc_organization
    workspaces = {
      name = var.organization_workspace_name
    }
  }
}

# The projects and network-hub stages were split into their own roots (audit H3),
# so this root now reads environment_config from gcp-projects and hub_network from
# gcp-network-hub. org_id / billing_account / admin_project_number still come from
# gcp-organization above.
data "terraform_remote_state" "projects" {
  backend = "cloud"
  config = {
    organization = var.tfc_organization
    workspaces = {
      name = var.projects_workspace_name
    }
  }
}

data "terraform_remote_state" "network_hub" {
  backend = "cloud"
  config = {
    organization = var.tfc_organization
    workspaces = {
      name = var.network_hub_workspace_name
    }
  }
}

locals {
  env_config = data.terraform_remote_state.projects.outputs.environment_config[var.environment]

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
          resource     = "//iam.googleapis.com/projects/${data.terraform_remote_state.organization.outputs.admin_project_number}/locations/global/workloadIdentityPools/*"
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

  # Effective VPC-SC policies: caller-supplied values override the defaults above.
  effective_vpc_sc_ingress_policies = length(var.vpc_sc_ingress_policies) > 0 ? var.vpc_sc_ingress_policies : tolist(local.default_vpc_sc_ingress_policies)
  effective_vpc_sc_egress_policies  = length(var.vpc_sc_egress_policies) > 0 ? var.vpc_sc_egress_policies : tolist(local.default_vpc_sc_egress_policies)
}

data "google_project" "host_project" {
  project_id = local.env_config.host_project_id
}

module "host" {
  source = "../../../modules/gcp/stages/host"

  project_id     = local.env_config.host_project_id
  project_prefix = var.project_prefix
  region         = local.env_config.region
  vpc_name       = "${var.project_prefix}-${var.environment}-vpc"
  vpc_cidr_block = local.env_config.cidr_block

  enable_networking          = true
  enable_shared_vpc_host     = true
  enable_deletion_protection = var.enable_deletion_protection

  enable_cloud_armor         = var.enable_cloud_armor
  enable_owasp_rules         = var.enable_owasp_rules
  enable_adaptive_protection = var.enable_adaptive_protection
  owasp_sensitivity          = var.owasp_sensitivity

  log_config_flow_sampling        = var.log_config_flow_sampling
  log_config_aggregation_interval = var.log_config_aggregation_interval

  labels = local.labels

  vpc_peerings = {
    "hub-peering" = {
      peer_network         = data.terraform_remote_state.network_hub.outputs.hub_network.vpc_self_link
      export_custom_routes = true
      import_custom_routes = true
    }
  }

  dns_zones = {
    "internal-peering" = {
      dns_name        = data.terraform_remote_state.network_hub.outputs.hub_network.dns_domain
      visibility      = "private"
      description     = "Peering zone to resolve internal hub DNS"
      peering_network = data.terraform_remote_state.network_hub.outputs.hub_network.vpc_self_link
      dnssec_enabled  = true
    }
  }

  enable_vpc_flow_logs_export           = true
  vpc_flow_logs_create_bigquery_dataset = true
  # BigQuery dataset IDs only allow alphanumerics and underscores — replace hyphens from environment name.
  vpc_flow_logs_bigquery_dataset_id = "vpc_flow_logs_${replace(var.environment, "-", "_")}"
  vpc_flow_logs_bigquery_location   = local.env_config.region
  vpc_flow_logs_retention_days      = var.vpc_flow_logs_retention_days

  # Only created when vpc_sc_access_policy_name is set (same gate as gcp-network-hub).
  # Passing a perimeter with a null access policy trips the vpc-sc module's validation,
  # which made the default plan of this root fail.
  vpc_service_controls = var.vpc_sc_access_policy_name == null ? {} : {
    "${var.environment}_perimeter" = {
      organization_id    = "organizations/${data.terraform_remote_state.organization.outputs.org_id}"
      access_policy_name = var.vpc_sc_access_policy_name
      perimeter_title    = coalesce(var.vpc_sc_perimeter_title, "${upper(var.environment)} Perimeter")
      perimeter_type     = "PERIMETER_TYPE_REGULAR"
      enable_dry_run     = var.vpc_sc_enable_dry_run
      # VPC-SC requires numeric project numbers, not project IDs.
      # data.google_project.host_project is declared above and resolves the number at plan time.
      protected_projects = [
        data.google_project.host_project.number
      ]
      restricted_services = var.vpc_sc_restricted_services
      ingress_policies    = local.effective_vpc_sc_ingress_policies
      egress_policies     = local.effective_vpc_sc_egress_policies
    }
  }
}

module "budget" {
  count  = var.monthly_budget_limit > 0 ? 1 : 0
  source = "../../../modules/gcp/governance/billing"

  billing_account      = data.terraform_remote_state.organization.outputs.billing_account
  project_id           = local.env_config.host_project_id
  project_name         = "${var.project_prefix}-${var.environment}"
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
  # pass the CMEK key from remote state:
  #   kms_key_name = data.terraform_remote_state.organization.outputs.cmek_key_names["budget-alerts"]
  # Ensure the Pub/Sub service agent has roles/cloudkms.cryptoKeyEncrypterDecrypter first.

  labels = local.labels
}

# =============================================================================
# SERVICE TEAM REGISTRY (audit H10)
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
  org_id          = data.terraform_remote_state.organization.outputs.org_id
  folder_id       = trimprefix(local.env_config.folder_id, "folders/")
  billing_account = trimprefix(data.terraform_remote_state.organization.outputs.billing_account, "billingAccounts/")

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
# SaaS SECRET BRIDGE (audit H9, hybrid option C — first increment)
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
    organization = var.tfc_organization
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
