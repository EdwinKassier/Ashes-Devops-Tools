variable "project_prefix" {
  description = "Prefix used by the organization root"
  type        = string
  default     = "my-org"
}

variable "environment" {
  description = "Application environment to deploy"
  type        = string
}

variable "provider_region" {
  description = "Default provider region for the Google provider"
  type        = string
  default     = "europe-west1"
}

variable "terraform_admin_email" {
  description = "Optional service account to impersonate for local runs"
  type        = string
  default     = null
}

variable "tfc_organization" {
  description = "Terraform Cloud organization used to read organization remote state"
  type        = string
}

variable "organization_workspace_name" {
  description = "Workspace name that stores the organization root state"
  type        = string
  default     = "organization"
}

variable "monthly_budget_limit" {
  description = "Monthly budget for this application environment"
  type        = number
  default     = 0
}

variable "budget_currency" {
  description = "Budget currency code"
  type        = string
  default     = "USD"
}

variable "enable_deletion_protection" {
  description = "Enable lifecycle protection for critical resources"
  type        = bool
  default     = false
}

variable "enable_cloud_armor" {
  description = "Enable Cloud Armor for internet-facing workloads"
  type        = bool
  default     = false
}

variable "enable_owasp_rules" {
  description = "Enable Cloud Armor OWASP managed rules"
  type        = bool
  default     = false
}

variable "enable_adaptive_protection" {
  description = "Enable Cloud Armor adaptive protection"
  type        = bool
  default     = false
}

variable "owasp_sensitivity" {
  description = "Cloud Armor OWASP sensitivity (1 is strictest, 4 is least strict)"
  type        = number
  default     = 4
}

variable "log_config_flow_sampling" {
  description = "VPC Flow Logs sampling rate"
  type        = number
  default     = 0.1
}

variable "log_config_aggregation_interval" {
  description = "VPC Flow Logs aggregation interval"
  type        = string
  default     = "INTERVAL_5_SEC"
}

variable "vpc_flow_logs_retention_days" {
  description = "Retention period for exported VPC flow logs"
  type        = number
  default     = 30
}

variable "extra_labels" {
  description = "Additional labels applied to the host project resources"
  type        = map(string)
  default     = {}
}

variable "vpc_sc_enable_dry_run" {
  description = "Whether the VPC-SC perimeter should run in dry-run mode"
  type        = bool
  default     = true
}

variable "vpc_sc_perimeter_title" {
  description = "Optional title override for the VPC-SC perimeter"
  type        = string
  default     = null
}

variable "vpc_sc_restricted_services" {
  description = "Restricted services enforced by the VPC-SC perimeter"
  type        = list(string)
  default = [
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudkms.googleapis.com",
    "pubsub.googleapis.com",
    "sqladmin.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com"
  ]
}

variable "vpc_sc_ingress_policies" {
  description = "Optional ingress policies for the VPC-SC perimeter"
  type = list(object({
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
  }))
  default = []
}

variable "vpc_sc_egress_policies" {
  description = "Optional egress policies for the VPC-SC perimeter"
  type = list(object({
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
  }))
  default = []
}

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
      organization_id = data.terraform_remote_state.organization.outputs.org_id
      perimeter_title = coalesce(var.vpc_sc_perimeter_title, "${upper(var.environment)} Perimeter")
      perimeter_type  = "PERIMETER_TYPE_REGULAR"
      enable_dry_run  = var.vpc_sc_enable_dry_run
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
