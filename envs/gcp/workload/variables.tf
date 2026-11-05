variable "project_prefix" {
  description = "Short name prefix used by the organization root. Must match the organization root's project_prefix exactly — used for resource naming consistency."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.project_prefix))
    error_message = "project_prefix must start with a lowercase letter and contain only lowercase letters, digits, and hyphens."
  }
}

variable "environment" {
  description = <<-EOT
    Application environment to deploy. Must match a key in the organization root's
    `environments` map (e.g., "dev", "staging", "prod"). A mismatch causes a
    plan-time failure when looking up environment_config[var.environment].
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,29}$", var.environment))
    error_message = "environment must be lowercase alphanumeric with optional hyphens (e.g., 'dev', 'staging', 'prod')."
  }
}

variable "region" {
  description = "Default Google Cloud region for this application environment (e.g. \"europe-west1\"). Must match the region used when provisioning spoke projects in the organization root."
  type        = string
  default     = "europe-west1"
}

variable "terraform_admin_email" {
  description = "Optional service account email to impersonate for local runs (format: name@project.iam.gserviceaccount.com)"
  type        = string
  default     = null

  validation {
    # Matches the strict SA-email form required by envs/gcp/organization/variables.tf's
    # terraform_admin_email: both roots impersonate this SA identically via the google
    # provider's `impersonate_service_account`, which only accepts a real GCP service
    # account email — a generic `user@domain.tld` address (previously accepted here) can
    # never be impersonated and would fail at provider-init time with a confusing error
    # instead of a clear validation message.
    condition     = var.terraform_admin_email == null || can(regex("^[^@]+@[^@]+\\.iam\\.gserviceaccount\\.com$", var.terraform_admin_email))
    error_message = "terraform_admin_email must be a GCP service account email (ends in .iam.gserviceaccount.com) or null."
  }
}

variable "tfc_organization" {
  description = "Terraform Cloud organization used to read organization remote state"
  type        = string
}

variable "organization_workspace_name" {
  description = "Workspace name that stores the organization root state (org_id, billing_account, admin_project_number, CMEK, tags)"
  type        = string
  default     = "gcp-organization"
}

variable "projects_workspace_name" {
  description = "Workspace name that stores the gcp-projects root state (environment_config / host project IDs)"
  type        = string
  default     = "gcp-projects"
}

variable "network_hub_workspace_name" {
  description = "Workspace name that stores the gcp-network-hub root state (hub_network for peering + DNS)"
  type        = string
  default     = "gcp-network-hub"
}

variable "monthly_budget_limit" {
  description = <<-EOT
    Monthly budget limit for this application environment in var.budget_currency.
    A value of 0 (the default) disables budget alerting entirely — the budget
    Pub/Sub topic and Cloud Function notifier are not created.
    Set a positive value to enable cost alerting (e.g., 1000 for USD 1,000/month).
  EOT
  type        = number
  default     = 0

  validation {
    condition     = var.monthly_budget_limit >= 0
    error_message = "monthly_budget_limit must be >= 0. Use 0 to disable budget alerts, or a positive number to set a limit."
  }
}

variable "budget_currency" {
  description = "ISO 4217 currency code for budget alerts (e.g., USD, EUR, GBP)"
  type        = string
  default     = "USD"

  validation {
    condition     = can(regex("^[A-Z]{3}$", var.budget_currency))
    error_message = "budget_currency must be a 3-letter ISO 4217 currency code (e.g., USD, EUR)."
  }
}

variable "enable_deletion_protection" {
  description = "Enable lifecycle protection to prevent accidental destruction of critical network resources (VPC, subnets, DNS zones). Set to false only during teardown — requires state manipulation before destroy. See docs/runbooks/cidr-expansion.md for the removal procedure."
  type        = bool
  default     = true
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
  description = "Cloud Armor OWASP managed rule sensitivity level: 1 = strictest (most blocks, lowest false-negative rate), 4 = most permissive (fewest blocks, highest false-negative rate). Default 2 is recommended for production."
  type        = number
  default     = 2

  validation {
    condition     = var.owasp_sensitivity >= 1 && var.owasp_sensitivity <= 4
    error_message = "owasp_sensitivity must be between 1 (strictest) and 4 (most permissive)."
  }
}

variable "log_config_flow_sampling" {
  description = "VPC Flow Logs packet-sampling rate (0.0–1.0). 0.1 = 10% of packets sampled. Recommended: 0.5 for dev/staging, 0.1 for prod (reduce Logging cost). Set to 0.0 to disable flow log collection while keeping the log bucket."
  type        = number
  default     = 0.1

  validation {
    condition     = var.log_config_flow_sampling >= 0.0 && var.log_config_flow_sampling <= 1.0
    error_message = "log_config_flow_sampling must be between 0.0 and 1.0."
  }
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

variable "vpc_sc_access_policy_name" {
  description = <<-EOT
    Bare numeric ID of the existing organisation-level Access Context Manager access policy
    that governs all VPC Service Controls perimeters in this org (e.g. '1234567890').
    Do NOT include the 'accessPolicies/' prefix.
    Find your policy ID: gcloud access-context-manager policies list --organization=ORG_ID
    When null (the default) no environment perimeter is created; set it to create one.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.vpc_sc_access_policy_name == null || can(regex("^[0-9]+$", var.vpc_sc_access_policy_name))
    error_message = "vpc_sc_access_policy_name must be a bare numeric ID (e.g. '1234567890'). Do not include the 'accessPolicies/' prefix."
  }
}

variable "vpc_sc_enable_dry_run" {
  description = <<-EOT
    When true (the default), VPC Service Controls logs violations but does NOT block any traffic (dry-run/simulation mode).
    When false, the perimeter is in ENFORCED mode and will block unauthorised cross-perimeter traffic.

    Google recommends dry-run FIRST: a perimeter that goes straight to enforcement can block all legitimate
    API traffic on a bad rule. Validate the violation logs (Cloud Logging / the VPC-SC violations dashboard),
    then PROMOTE to enforcement by setting this false.
    NOTE: dry-run provides NO data-exfiltration protection — do not leave a production perimeter in dry-run.
    See docs/architecture/network-topology.md and docs/known-gaps.md (G11).
  EOT
  type        = bool
  default     = true
}

variable "vpc_sc_dry_run_restricted_services" {
  description = "Optional restricted_services to TRIAL in a staged dry-run spec while the perimeter stays ENFORCED (only meaningful with vpc_sc_enable_dry_run = false). Status keeps enforcing vpc_sc_restricted_services; the dry-run spec logs what this list would block. Default null = no staged spec."
  type        = list(string)
  default     = null
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

# -----------------------------------------------------------------------------
# SERVICE TEAM REGISTRY (audit H10)
#
# Data-driven onboarding: a service team is a map entry, not a new module block.
# Default empty, so no service projects are created unless an admin declares them.
# -----------------------------------------------------------------------------

variable "service_teams" {
  description = <<-EOT
    Registry of application service teams for this environment. Each entry creates
    a GCP service project in the environment's folder, attaches it to the Shared
    VPC, and grants the team's admin Google Group least-privilege roles. Adding or
    removing a team is a change to this map (config), not a code change to main.tf.

    Promote a team from one environment to the next by adding the same entry to the
    next environment's tfvars. See docs/runbooks/promotion.md.

    Fields per team (keyed by the team/project short name):
      project_admin_group_email    (required) admin Google Group for the project.
      activate_apis                APIs to enable (default []).
      project_admin_roles          least-privilege roles for the admin group
                                   (default []; primitive and org/folder-level
                                   roles are rejected by the workload module).
      enable_shared_vpc_attachment attach to the Shared VPC host (default true).
      enable_gke_network_user      also grant the GKE robot SA networkUser
                                   (default false; set only for GKE projects).
      shared_vpc_subnets           subnets to grant, keyed by a label, each with
                                   region and subnet_name (default {}; at least one
                                   is required when attachment is enabled).
      labels                       extra project labels (default {}).
  EOT
  type = map(object({
    project_admin_group_email    = string
    activate_apis                = optional(list(string), [])
    project_admin_roles          = optional(list(string), [])
    enable_shared_vpc_attachment = optional(bool, true)
    enable_gke_network_user      = optional(bool, false)
    shared_vpc_subnets = optional(map(object({
      region      = string
      subnet_name = string
    })), {})
    labels = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.service_teams) : can(regex("^[a-z][a-z0-9-]{0,24}$", k))])
    error_message = "Each service team key must be a project-name-safe slug: start with a lowercase letter, then lowercase letters, digits, or hyphens, 25 characters or fewer."
  }

  validation {
    condition     = alltrue([for t in values(var.service_teams) : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", t.project_admin_group_email))])
    error_message = "Each service team must set a valid project_admin_group_email."
  }

  validation {
    condition     = alltrue([for t in values(var.service_teams) : !t.enable_shared_vpc_attachment || length(t.shared_vpc_subnets) > 0])
    error_message = "A service team with enable_shared_vpc_attachment = true (the default) must grant at least one entry in shared_vpc_subnets."
  }
}

# -----------------------------------------------------------------------------
# SaaS secret bridge (audit H9, hybrid option C — first increment)
#
# Opt-in. When enabled, this workload reads the Supabase outputs from a saas-<name>
# workspace and writes them into a GCP Secret Manager secret in the host project,
# so a GCP runtime can use Supabase as a managed datastore by secret reference.
# Default off: no SaaS coupling, and the workload reads no saas state.
#
# NOTE: the bridged values (service role key, database password) are sensitive and
# will be stored as a secret version, so they are persisted in THIS root's state as
# well as the saas root's. Teams that require zero secret duplication should instead
# create the secret container with modules/gcp/data/secret-manager and set the value
# out of band, leaving this bridge disabled.
# -----------------------------------------------------------------------------

variable "enable_saas_secret_bridge" {
  description = "Bridge Supabase connection details from a saas-<name> workspace into a GCP Secret Manager secret in the host project (opt-in, audit H9). Default false."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_saas_secret_bridge || (var.saas_workspace_name != null && length(var.saas_secret_accessor_members) > 0)
    error_message = "enable_saas_secret_bridge = true requires saas_workspace_name and at least one saas_secret_accessor_members entry (the runtime that reads the secret)."
  }
}

variable "saas_workspace_name" {
  description = "TFC workspace (saas-<name>) to read Supabase outputs from when enable_saas_secret_bridge is true."
  type        = string
  default     = null
}

variable "saas_secret_name" {
  description = "Name of the Secret Manager secret that holds the bridged Supabase connection JSON (api_url, service_role_key, database_password)."
  type        = string
  default     = "supabase-connection"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,255}$", var.saas_secret_name))
    error_message = "saas_secret_name must be 1-255 characters of letters, digits, hyphens, or underscores."
  }
}

variable "saas_secret_accessor_members" {
  description = "IAM members granted read access to the bridged Supabase secret (e.g. the app runtime service account), in serviceAccount:... form. Required when the bridge is enabled."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for m in var.saas_secret_accessor_members : can(regex("^(serviceAccount|user|group):", m))])
    error_message = "Each saas_secret_accessor_members entry must be a prefixed IAM member (serviceAccount:, user:, or group:)."
  }
}

# -----------------------------------------------------------------------------
# APPLICATION GOLDEN PATH (modules/gcp/stages/app-services)
#
# Default empty / off: nothing is created. See docs/guides/deploying-a-service.md.
# -----------------------------------------------------------------------------

variable "app_services" {
  description = <<-EOT
    Application services for this environment, keyed by service name (2-22 chars).
    Each entry creates an Artifact Registry repo, a runtime SA and an internal
    Cloud Run v2 service in the host project; `database = {}` adds a private-IP
    Cloud SQL Postgres with IAM auth, and `github = { repository_id = "<numeric>" }`
    adds a WIF-bound deploy SA (needs enable_app_deploy_wif = true). The full,
    typed shape (and every default) is the `services` variable of
    modules/gcp/stages/app-services, which validates it; see
    docs/guides/deploying-a-service.md for a worked entry.
  EOT
  type        = any
  default     = {}
}

variable "app_subnetwork_id" {
  description = "Subnet ID (projects/<p>/regions/<r>/subnetworks/<s>) for Cloud Run Direct VPC egress and GKE nodes. Null uses the first private subnet of the env VPC."
  type        = string
  default     = null
}

variable "artifact_registry_kms_key_name" {
  description = "Optional CMEK key for every app Artifact Registry repo. Null uses Google-managed encryption."
  type        = string
  default     = null
}

variable "enable_app_deploy_wif" {
  description = "Create the app-deploy Workload Identity pool (GitHub OIDC) in the env host project, separate from the infra pool in gcp-bootstrap. Required for any app_services entry that sets `github`."
  type        = bool
  default     = false
}

variable "app_deploy_wif_pool_id" {
  description = "ID of the app-deploy WIF pool. Null defaults to \"apps-<environment>\"."
  type        = string
  default     = null
}

variable "github_repository_owner_id" {
  description = "Optional numeric GitHub owner (org) ID; when set the app-deploy WIF provider also requires repository_owner_id to match."
  type        = string
  default     = null
}

variable "enable_gke_autopilot" {
  description = "Create one private GKE Autopilot cluster for the environment (default off)."
  type        = bool
  default     = false
}

variable "gke_master_ipv4_cidr_block" {
  description = "The /28 control-plane CIDR for the env GKE Autopilot cluster."
  type        = string
  default     = "172.16.0.0/28"
}

variable "gke_master_authorized_networks" {
  description = "CIDR blocks allowed to reach the GKE control plane."
  type = list(object({
    cidr_block   = string
    display_name = optional(string)
  }))
  default = []
}

variable "gke_cluster_secondary_range_name" {
  description = "Subnet secondary range for GKE pod IPs. Null lets GKE allocate one."
  type        = string
  default     = null
}

variable "gke_services_secondary_range_name" {
  description = "Subnet secondary range for GKE Service IPs. Null lets GKE allocate one."
  type        = string
  default     = null
}
