# Environment Configuration - Development
# This file demonstrates how to piggyback on the organization setup
# The provider is already configured to impersonate the Terraform Admin SA

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
  default     = "dev"
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
  # Extract the configuration for the 'dev' environment from the organization outputs
  dev_config = data.terraform_remote_state.organization.outputs.environment_config[var.environment]

  # Extract the host project ID
  dev_host_project_id = local.dev_config.projects["host"].project_id

  hub_network = data.terraform_remote_state.organization.outputs.hub_network
}

# =============================================================================
# DATA SOURCES
# =============================================================================

# Use the retrieved Project ID
data "google_project" "dev_host_project" {
  project_id = local.dev_host_project_id
}

# =============================================================================
# ENVIRONMENT FOUNDATION (Host Module)
# =============================================================================

module "host" {
  source = "../../modules/host"

  project_id     = local.dev_host_project_id
  project_prefix = var.project_prefix
  region         = local.dev_config.region # Centralized from organisation layer


  # IP Addressing: Consumed from Organization layer (auto-assigned or explicit)
  vpc_cidr_block = local.dev_config.cidr_block

  # Enable core features
  enable_networking      = true
  enable_shared_vpc_host = true

  # Cost Optimization: Low sampling for development
  log_config_flow_sampling = 0.1

  # Developement-specific configuration
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

  # GKE Secondary Ranges (Example)
  # secondary_ranges = {
  #   "${local.dev_config.region}-a" = [
  #     { range_name = "pods", ip_cidr_range = "10.100.0.0/16" },
  #     { range_name = "services", ip_cidr_range = "10.101.0.0/20" }
  #   ]
  # }

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
      dnssec_enabled  = true
    }
  }

  # VPC Flow Logs Export (Centralized network analytics)
  enable_vpc_flow_logs_export           = true
  vpc_flow_logs_create_bigquery_dataset = true
  vpc_flow_logs_bigquery_dataset_id     = "vpc_flow_logs_${var.environment}"
  vpc_flow_logs_bigquery_location       = local.dev_config.region
  vpc_flow_logs_retention_days          = 30 # Lower retention for dev

  # VPC Service Controls (Security Perimeter) - Dry Run for Dev
  # DRY RUN: Logs violations without blocking to catch misconfigurations early
  # Review Access Transparency logs before switching to enforced mode
  vpc_service_controls = {
    "dev_perimeter" = {
      organization_id = data.terraform_remote_state.organization.outputs.org_id
      perimeter_title = "Development Perimeter (Dry Run)"
      perimeter_type  = "PERIMETER_TYPE_REGULAR"
      enable_dry_run  = true # Non-blocking for developer flexibility
      protected_projects = [
        local.dev_host_project_id
      ]

      # Comprehensive list of sensitive services to protect
      # Even in dry-run, this validates all access patterns
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
              # This permits Terraform Cloud and GitHub Actions to manage resources
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

      # Egress Policy: Allow access to external package registries (npm, PyPI, etc.)
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
  project_id           = local.dev_host_project_id
  project_name         = "${var.project_prefix}-${var.environment}"
  monthly_budget_limit = 500 # Lower budget for dev environment
  currency_code        = "USD"

  # Monitor all projects in this environment
  projects = [
    "projects/${data.google_project.dev_host_project.number}"
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
# EXAMPLE RESOURCES
# =============================================================================

# Example resource to verify detailed permissions
resource "google_storage_bucket" "dev_state_bucket" {
  name          = "${var.project_prefix}-dev-state-${data.google_project.dev_host_project.number}"
  location      = "EU"
  project       = data.google_project.dev_host_project.project_id
  force_destroy = true

  uniform_bucket_level_access = true

  labels = {
    environment = var.environment
    purpose     = "state-storage"
    managed-by  = "terraform"
  }
}
