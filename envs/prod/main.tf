# Production Environment Configuration
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
  default     = "prod"
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
  # Extract the configuration for the 'prod' environment
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

  # Production safeguards
  enable_deletion_protection = true

  # Production WAF Security
  enable_cloud_armor         = true
  enable_owasp_rules         = true
  enable_adaptive_protection = true
  owasp_sensitivity          = 2 # Moderate strictness

  # Visibility: Full logging for production forensics
  log_config_flow_sampling        = 1.0
  log_config_aggregation_interval = "INTERVAL_5_SEC"

  # Production-specific configuration
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
    criticality = "high"
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
      dnssec_enabled  = true
    }
  }

  # VPC Flow Logs Export (Full forensics and compliance)
  enable_vpc_flow_logs_export           = true
  vpc_flow_logs_create_bigquery_dataset = true
  vpc_flow_logs_bigquery_dataset_id     = "vpc_flow_logs_${var.environment}"
  vpc_flow_logs_bigquery_location       = local.config.region
  vpc_flow_logs_retention_days          = 365 # Full year retention for compliance

  # VPC Service Controls (Security Perimeter)
  # ENFORCED: VPC-SC now actively prevents data exfiltration
  # Ensure all access patterns have been validated via dry-run logs before enforcement
  vpc_service_controls = {
    "prod_perimeter" = {
      organization_id = data.terraform_remote_state.organization.outputs.org_id
      perimeter_title = "Production Perimeter"
      perimeter_type  = "PERIMETER_TYPE_REGULAR"
      enable_dry_run  = false # ENFORCED - data exfiltration protection active
      protected_projects = [
        local.host_project_id
      ]

      # Comprehensive list of sensitive services to protect
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
# RESOURCES
# =============================================================================

# Production state bucket with hardened security settings
resource "google_storage_bucket" "state_bucket" {
  name     = "${var.project_prefix}-${var.environment}-state-${data.google_project.host_project.number}"
  location = "EU"
  project  = data.google_project.host_project.project_id

  # Production hardening
  force_destroy               = false
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  # Lifecycle rule to manage old versions (cost optimization)
  lifecycle_rule {
    condition {
      num_newer_versions = 5
    }
    action {
      type = "Delete"
    }
  }

  # Lifecycle rule to archive old versions after 30 days
  lifecycle_rule {
    condition {
      age                = 30
      with_state         = "ARCHIVED"
      num_newer_versions = 1
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  labels = {
    environment = var.environment
    purpose     = "state-storage"
    managed-by  = "terraform"
    criticality = "high"
  }
}

# =============================================================================
# BUDGET ALERTS (Per-Environment Spend Monitoring)
# =============================================================================

module "budget" {
  source = "../../modules/governance/billing"

  billing_account      = data.terraform_remote_state.organization.outputs.billing_account
  project_id           = local.host_project_id
  project_name         = "${var.project_prefix}-${var.environment}"
  monthly_budget_limit = 5000 # Adjust based on expected production spend
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
# SHARED VPC SERVICE PROJECTS (Workload Attachment)
# =============================================================================
# 
# Example: To attach workload service projects to this host VPC, uncomment
# and configure the shared_vpc_service_projects variable in the host module:
#
# In the host module call above, add:
#
#   shared_vpc_service_projects = {
#     "my-org-prod-app-1234" = {
#       # Grant specific subnet access to service project members
#       subnet_iam_bindings = [
#         {
#           subnet = "my-org-prod-vpc-private-us-central1-a"
#           region = local.config.region
#           member = "serviceAccount:app-sa@my-org-prod-app-1234.iam.gserviceaccount.com"
#         }
#       ]
#       
#       # Or grant access to all subnets
#       grant_network_user_to_all_subnets = true
#       network_user_members = [
#         "serviceAccount:app-sa@my-org-prod-app-1234.iam.gserviceaccount.com"
#       ]
#       
#       # Enable GKE permissions if deploying Kubernetes
#       enable_gke_permissions = true
#     }
#   }
#
# Service project IDs should be created via the organisation layer's project
# factory and consumed from remote state.

