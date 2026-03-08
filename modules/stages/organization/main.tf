# Organization Structure
module "organization" {
  source = "../../iam/organization"

  domain      = var.domain
  project_id  = var.admin_project_id
  customer_id = var.customer_id

  # Default organization admins
  org_admin_members = distinct(concat(
    ["user:${var.admin_email}"],
    var.break_glass_user != null ? ["user:${var.break_glass_user}"] : [],
    [for group in var.organization_admin_groups : "group:${group}"]
  ))

  # Default billing admins
  billing_admin_members = distinct(concat(
    ["user:${var.admin_email}"],
    [for group in var.billing_admin_groups : "group:${group}"]
  ))

  # Organizational Units (excluding projects, they are created later)
  organizational_units = var.environments
}

# Grant Terraform Admin SA rights on the created folders
resource "google_folder_iam_member" "terraform_admin_folder_roles" {
  for_each = {
    for pair in flatten([
      for folder_key, folder in module.organization.folders : [
        for role in [
          "roles/resourcemanager.folderAdmin",
          "roles/resourcemanager.projectCreator",
          "roles/billing.projectManager",
          "roles/compute.networkAdmin"
          ] : {
          key    = "${folder_key}-${role}"
          folder = folder.id
          role   = role
        }
      ]
    ]) : pair.key => pair
  }

  folder = each.value.folder
  role   = each.value.role
  member = "serviceAccount:${var.terraform_admin_email}"
}


# Centralized Audit Logs
module "cmek" {
  source = "../../governance/kms"

  project_id   = var.admin_project_id
  keyring_name = "${var.project_prefix}-org-cmek"
  location     = var.default_region

  keys = {
    "audit-logs" = {
      encrypter_decrypters = [
        "serviceAccount:service-${var.admin_project_number}@gs-project-accounts.iam.gserviceaccount.com",
      ]
    }
    "audit-analytics" = {
      encrypter_decrypters = [
        "serviceAccount:bq-${var.admin_project_number}@bigquery-encryption.iam.gserviceaccount.com",
      ]
    }
    "billing-alerts" = {
      encrypter_decrypters = [
        "serviceAccount:service-${var.admin_project_number}@gcp-sa-pubsub.iam.gserviceaccount.com",
      ]
    }
    "scc-notifications" = {
      encrypter_decrypters = [
        "serviceAccount:service-${var.admin_project_number}@gcp-sa-pubsub.iam.gserviceaccount.com",
      ]
    }
    "billing-export" = {
      encrypter_decrypters = [
        "serviceAccount:bq-${var.admin_project_number}@bigquery-encryption.iam.gserviceaccount.com",
      ]
    }
  }
}

module "audit_logs" {
  source = "../../governance/cloud-audit-logs"

  project_id         = var.admin_project_id
  bucket_location    = var.default_region
  log_retention_days = 365
  org_id             = var.org_id
  kms_key_name       = module.cmek.key_names["audit-logs"]

  # Enable BigQuery Analytics for improved security investigation
  enable_bigquery_analytics = true
  bigquery_location         = var.default_region
  bigquery_kms_key_name     = module.cmek.key_names["audit-analytics"]
}

# Security Command Center Notifications
module "scc_notifications" {
  source = "../../governance/scc"

  org_id            = var.org_id
  project_id        = var.admin_project_id
  pubsub_topic_name = "scc-findings"
  config_id         = "scc-notify-all-active"
  filter            = "state=\"ACTIVE\""
  kms_key_name      = module.cmek.key_names["scc-notifications"]
}

# Resource Manager Tags (Metadata & Governance)
module "tags" {
  source = "../../governance/tags"

  org_id = var.org_id

  tags = {
    "environment"         = sort(keys(var.environments))
    "business-unit"       = ["engineering", "product", "sales"]
    "data-classification" = ["public", "internal", "confidential", "restricted"]
  }
}

# Organization Policies (Governance)
module "org_policies" {
  source = "../../governance/org-policy"

  parent = "organizations/${module.organization.organization_id}"

  list_policies = [
    {
      constraint     = "gcp.resourceLocations"
      allowed_values = var.allowed_regions
      denied_values  = null
      allow_all      = null
      deny_all       = null
    },
    {
      constraint     = "iam.allowedPolicyMemberDomains"
      allowed_values = [var.customer_id]
      denied_values  = null
      allow_all      = null
      deny_all       = null
    },
    # Network Security: Restrict VPC peering to within the organization only
    {
      constraint     = "compute.restrictVpcPeering"
      allowed_values = ["under:organizations/${module.organization.organization_id}"]
      denied_values  = null
      allow_all      = null
      deny_all       = null
    }
  ]

  boolean_policies = [
    {
      constraint = "compute.skipDefaultNetworkCreation"
      enforce    = true
    },
    {
      constraint = "compute.requireShieldedVm"
      enforce    = true
    },
    {
      constraint = "sql.restrictPublicIp"
      enforce    = true
    },
    {
      constraint = "iam.disableServiceAccountKeyCreation"
      enforce    = true
    },
    {
      constraint = "compute.disableSerialPortAccess"
      enforce    = true
    },
    {
      constraint = "storage.uniformBucketLevelAccess"
      enforce    = true
    },
    # CIS 1.4: Disable automatic IAM grants for default service accounts
    {
      constraint = "iam.automaticIamGrantsForDefaultServiceAccounts"
      enforce    = true
    },
    # CIS 4.9: Restrict VM external IP access (deny by default)
    {
      constraint = "compute.vmExternalIpAccess"
      enforce    = true
    },
    # Security: Disable service account key upload
    {
      constraint = "iam.disableServiceAccountKeyUpload"
      enforce    = true
    },
    # Security: Require VPC Connector for Cloud Functions
    {
      constraint = "cloudfunctions.requireVPCConnector"
      enforce    = true
    },
    # Security: Require Private Google Access for secure API access
    {
      constraint = "compute.requirePrivateGoogleAccess"
      enforce    = true
    }
  ]
}

# Folder-level Organization Policies for Production
module "prod_folder_policies" {
  source = "../../governance/org-policy"
  for_each = {
    for env_key in var.strict_folder_policy_environment_keys :
    env_key => module.organization.folders[env_key]
    if contains(keys(module.organization.folders), env_key)
  }

  parent = each.value.name

  list_policies = []

  boolean_policies = [
    {
      constraint = "compute.disableNestedVirtualization"
      enforce    = true
    },
    {
      constraint = "compute.disableGuestAttributesAccess"
      enforce    = true
    },
    {
      constraint = "compute.requireOsLogin"
      enforce    = true
    },
    {
      # Network Security: Force traffic through Cloud NAT / Load Balancers
      constraint = "compute.disableInternetGatewayUse"
      enforce    = true
    }
  ]
}

# Essential Contacts
resource "google_essential_contacts_contact" "security" {
  count = var.security_contact_email != null ? 1 : 0

  parent                              = "organizations/${var.org_id}"
  email                               = var.security_contact_email
  language_tag                        = "en-US"
  notification_category_subscriptions = ["SECURITY", "TECHNICAL", "LEGAL", "PRIVACY", "ALL"]
}

resource "google_essential_contacts_contact" "billing" {
  count = var.billing_contact_email != null ? 1 : 0

  parent                              = "organizations/${var.org_id}"
  email                               = var.billing_contact_email
  language_tag                        = "en-US"
  notification_category_subscriptions = ["BILLING"]
}

# Org Budget
module "org_budget" {
  count  = var.monthly_budget_amount > 0 ? 1 : 0
  source = "../../governance/billing"

  billing_account      = var.billing_account
  project_id           = var.admin_project_id
  project_name         = "${var.project_prefix}-org"
  monthly_budget_limit = var.monthly_budget_amount
  currency_code        = var.budget_currency
  kms_key_name         = module.cmek.key_names["billing-alerts"]

  # Monitor the entire Billing Account by defaulting 'projects' to empty (null)
  # projects = ["projects/${var.admin_project_number}"]
}

# FinOps: Billing Data Export
# -----------------------------------------------------------------------------
resource "google_bigquery_dataset" "billing_export" {
  dataset_id                  = "billing_export"
  friendly_name               = "Billing Data Export"
  description                 = "Dataset for Cloud Billing export data"
  location                    = var.default_region
  project                     = var.admin_project_id
  default_table_expiration_ms = null # Billing data should be persisted

  default_encryption_configuration {
    kms_key_name = module.cmek.key_names["billing-export"]
  }
}
