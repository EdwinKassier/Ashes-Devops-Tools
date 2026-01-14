# UAT Environment Configuration
# Consumes infrastructure from the Organization layer via Remote State

# =============================================================================
# VARIABLES
# =============================================================================

variable "project_prefix" {
  description = "Prefix used in organization setup"
  type        = string
  default     = "my-org"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "uat"
}

variable "tfc_organization" {
  description = "Terraform Cloud organization name for remote state access"
  type        = string
}

variable "tfc_workspace_name" {
  description = "Name of the organization workspace to read remote state from"
  type        = string
  default     = "organisation"
}

# =============================================================================
# REMOTE STATE (Organization Outputs)
# =============================================================================

# Fetch downstream configuration from the Organization Workspace
data "terraform_remote_state" "organization" {
  backend = "cloud"
  config = {
    organization = var.tfc_organization
    workspaces = {
      name = var.tfc_workspace_name
    }
  }
}

locals {
  # Extract the configuration for the 'uat' environment
  config = data.terraform_remote_state.organization.outputs.environment_config[var.environment]

  # Extract the host project ID
  host_project_id = local.config.projects["host"].project_id

  hub_network = data.terraform_remote_state.organization.outputs.hub_network
}

# =============================================================================
# DATA SOURCES
# =============================================================================

# Use the retrieved Project ID
data "google_project" "host_project" {
  project_id = local.host_project_id
}

# =============================================================================
# ENVIRONMENT FOUNDATION (Host Module)
# =============================================================================

module "host" {
  source = "../../modules/host"

  project_id     = local.host_project_id
  project_prefix = var.project_prefix
  region         = local.config.region # Centralized from organisation layer


  # IP Addressing: Consumed from Organization layer
  vpc_cidr_block = local.config.cidr_block

  # Enable core features
  enable_networking      = true
  enable_shared_vpc_host = true

  # WAF Protection: Pre-Production Security Testing
  enable_cloud_armor         = true
  enable_owasp_rules         = true
  enable_adaptive_protection = true
  owasp_sensitivity          = 3 # Less strict than prod for testing

  # Balanced logging for UAT
  log_config_flow_sampling = 0.5

  # UAT-specific configuration
  vpc_name = "${var.project_prefix}-${var.environment}-vpc"

  # Future: Attach Service Projects here
  # shared_vpc_service_projects = {
  #   "service-project-1" = {
  #     subnet_iam_bindings = []
  #   }
  # }

  # Labels
  labels = {
    environment = var.environment
    managed-by  = "terraform"
  }

  # Connection to Hub
  vpc_peerings = {
    "hub-peering" = {
      peer_network         = local.hub_network.vpc_self_link
      export_custom_routes = true
      import_custom_routes = true
    }
  }

  # DNS Peering to Hub (Resolve internal organization names)
  dns_zones = {
    "internal-peering" = {
      dns_name        = local.hub_network.dns_domain
      visibility      = "private"
      description     = "Peering zone to resolve internal Hub DNS"
      peering_network = local.hub_network.vpc_self_link
      dnssec_enabled  = true # Parity with production
    }
  }

  # VPC Flow Logs Export (Centralized network analytics)
  enable_vpc_flow_logs_export           = true
  vpc_flow_logs_create_bigquery_dataset = true
  vpc_flow_logs_bigquery_dataset_id     = "vpc_flow_logs_${var.environment}"
  vpc_flow_logs_bigquery_location       = local.config.region
  vpc_flow_logs_retention_days          = 60 # Moderate retention for UAT

  # VPC Service Controls (Security Perimeter) - Parity with Prod
  # ENFORCED: VPC-SC now actively prevents data exfiltration
  vpc_service_controls = {
    "uat_perimeter" = {
      organization_id = data.terraform_remote_state.organization.outputs.org_id
      perimeter_title = "UAT Perimeter"
      perimeter_type  = "PERIMETER_TYPE_REGULAR"
      enable_dry_run  = true # DRY RUN - Safety net before production enforcement
      protected_projects = [
        local.host_project_id
      ]

      # Comprehensive list of sensitive services to protect (parity with prod)
      restricted_services = [
        "bigquery.googleapis.com",
        "storage.googleapis.com",
        "secretmanager.googleapis.com",
        "cloudkms.googleapis.com",
        "pubsub.googleapis.com",
        "sqladmin.googleapis.com",
        "container.googleapis.com",
        "artifactregistry.googleapis.com"
      ]

      # Ingress Policy: Allow CI/CD pipelines (Terraform Cloud / GitHub Actions)
      ingress_policies = [
        {
          identity_type = "ANY_IDENTITY"
          sources = [
            {
              # Allow access from organization's Workload Identity pool
              resource = "//iam.googleapis.com/projects/${data.terraform_remote_state.organization.outputs.admin_project_number}/locations/global/workloadIdentityPools/*"
            }
          ]
          operations = [
            { service_name = "storage.googleapis.com" },
            { service_name = "bigquery.googleapis.com" },
            { service_name = "container.googleapis.com" }
          ]
        }
      ]

      # Egress Policy: Allow controlled external access
      egress_policies = [
        {
          identity_type = "ANY_IDENTITY"
          resources     = ["*"]
          operations = [
            { service_name = "storage.googleapis.com" } # For GCS-backed mirrors
          ]
        }
      ]
    }
  }
}

# =============================================================================
# BUDGET ALERTS (Cost Monitoring)
# =============================================================================

module "budget" {
  source = "../../modules/governance/billing"

  billing_account      = data.terraform_remote_state.organization.outputs.billing_account
  project_id           = local.host_project_id
  project_name         = "${var.project_prefix}-${var.environment}"
  monthly_budget_limit = 1000 # Medium budget for UAT (pre-production testing)
  currency_code        = "USD"

  # Monitor all projects in this environment
  projects = [
    "projects/${data.google_project.host_project.number}"
  ]

  # Environment-specific labels for filtering
  label_filters = {
    environment = var.environment
  }

  tags = {
    environment = var.environment
    managed-by  = "terraform"
  }
}

# =============================================================================
# RESOURCES
# =============================================================================

resource "google_storage_bucket" "state_bucket" {
  name                        = "${var.project_prefix}-${var.environment}-state-${data.google_project.host_project.number}"
  location                    = "EU"
  project                     = data.google_project.host_project.project_id
  force_destroy               = true
  uniform_bucket_level_access = true

  labels = {
    environment = var.environment
    purpose     = "state-storage"
    managed-by  = "terraform"
  }
}

