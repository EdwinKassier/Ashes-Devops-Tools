# This root depends on the organization root (envs/organization) via remote state.
# Trade-offs of this coupling:
#   Pro: avoids re-declaring org-level outputs (billing account, folder IDs, hub network).
#   Con: envs/apps cannot be planned or applied in isolation — the organization workspace
#        must exist and its outputs must be populated first.
# If you are onboarding a new environment, run envs/organization first.
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

locals {
  env_config = data.terraform_remote_state.organization.outputs.environment_config[var.environment]

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
}

locals {
  effective_vpc_sc_ingress_policies = length(var.vpc_sc_ingress_policies) > 0 ? var.vpc_sc_ingress_policies : tolist(local.default_vpc_sc_ingress_policies)
  effective_vpc_sc_egress_policies  = length(var.vpc_sc_egress_policies) > 0 ? var.vpc_sc_egress_policies : tolist(local.default_vpc_sc_egress_policies)
}

data "google_project" "host_project" {
  project_id = local.env_config.host_project_id
}

module "host" {
  source = "../../modules/host"

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
      peer_network         = data.terraform_remote_state.organization.outputs.hub_network.vpc_self_link
      export_custom_routes = true
      import_custom_routes = true
    }
  }

  dns_zones = {
    "internal-peering" = {
      dns_name        = data.terraform_remote_state.organization.outputs.hub_network.dns_domain
      visibility      = "private"
      description     = "Peering zone to resolve internal hub DNS"
      peering_network = data.terraform_remote_state.organization.outputs.hub_network.vpc_self_link
      dnssec_enabled  = true
    }
  }

  enable_vpc_flow_logs_export           = true
  vpc_flow_logs_create_bigquery_dataset = true
  vpc_flow_logs_bigquery_dataset_id     = "vpc_flow_logs_${var.environment}"
  vpc_flow_logs_bigquery_location       = local.env_config.region
  vpc_flow_logs_retention_days          = var.vpc_flow_logs_retention_days

  vpc_service_controls = {
    "${var.environment}_perimeter" = {
      organization_id = "organizations/${data.terraform_remote_state.organization.outputs.org_id}"
      perimeter_title = coalesce(var.vpc_sc_perimeter_title, "${upper(var.environment)} Perimeter")
      perimeter_type  = "PERIMETER_TYPE_REGULAR"
      enable_dry_run  = var.vpc_sc_enable_dry_run
      # TODO: Replace with the numeric project NUMBER (not ID).
      # Use: data "google_project" "host" { project_id = local.env_config.host_project_id }
      # Then: data.google_project.host.number
      # Currently passing project ID as a placeholder — VPC-SC requires numeric project numbers.
      protected_projects = [
        local.env_config.host_project_id
      ]
      restricted_services = var.vpc_sc_restricted_services
      ingress_policies    = local.effective_vpc_sc_ingress_policies
      egress_policies     = local.effective_vpc_sc_egress_policies
    }
  }
}

module "budget" {
  count  = var.monthly_budget_limit > 0 ? 1 : 0
  source = "../../modules/governance/billing"

  billing_account      = data.terraform_remote_state.organization.outputs.billing_account
  project_id           = local.env_config.host_project_id
  project_name         = "${var.project_prefix}-${var.environment}"
  monthly_budget_limit = var.monthly_budget_limit
  currency_code        = var.budget_currency

  projects = [
    "projects/${data.google_project.host_project.number}"
  ]

  label_filters = {
    environment = var.environment
  }

  tags = local.labels
}
