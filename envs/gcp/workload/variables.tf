variable "landing_zone_config_path" {
  description = "Path to the single-source landing-zone config (YAML; schema config/landing-zone.example.yaml), absolute or relative to this root. Null = ../../../config/landing-zone.yaml; \"\" disables the lookup. Read only if the file exists; explicit variables win over its values. Its `presets` list (and gcp.workload.presets_by_environment) loads examples/presets/<name>.yaml overlays."
  type        = string
  default     = null
}

variable "project_prefix" {
  description = "Short name prefix used by the organization root (resource naming). Null = org.prefix from config/landing-zone.yaml, the same source as every other GCP root."
  type        = string
  default     = null

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", coalesce(var.project_prefix, local.cfg.project_prefix, "!unset")))
    error_message = "project_prefix is unset or invalid: set var.project_prefix or org.prefix in config/landing-zone.yaml. It must start with a lowercase letter and contain only lowercase letters, digits, and hyphens."
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
  description = "Default Google Cloud region for this application environment (e.g. \"europe-west1\"). Must match the region used when provisioning spoke projects. Null = gcp.environments[<environment>].region from config/landing-zone.yaml, else org.regions.gcp, else europe-west2."
  type        = string
  default     = null
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
  description = "Terraform Cloud organization used to read organization remote state. Null = org.tfc.organization from config/landing-zone.yaml."
  type        = string
  default     = null

  validation {
    condition     = coalesce(var.tfc_organization, local.cfg.tfc_organization, "!unset") != "!unset"
    error_message = "tfc_organization is unset: set var.tfc_organization or org.tfc.organization in config/landing-zone.yaml."
  }
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

# -----------------------------------------------------------------------------
# Stage contract overrides (FAST-style). Each one, when set (here or as
# gcp.contracts.<layer> in config/landing-zone.yaml), replaces the matching
# terraform_remote_state read entirely — the upstream workspace is not read.
# -----------------------------------------------------------------------------

variable "organization_contract" {
  description = "gcp-organization stage contract: org_id (numeric), billing_account (billingAccounts/XXXXXX-XXXXXX-XXXXXX or bare ID) and admin_project_number. Null = gcp.contracts.organization from config/landing-zone.yaml, else read from the gcp-organization workspace's remote state."
  type = object({
    org_id               = string
    billing_account      = string
    admin_project_number = string
  })
  default = null

  validation {
    condition     = var.organization_contract == null || (can(regex("^[0-9]+$", try(var.organization_contract.org_id, ""))) && can(regex("^[0-9]+$", try(var.organization_contract.admin_project_number, ""))))
    error_message = "organization_contract.org_id and admin_project_number must be numeric."
  }
}

variable "projects_contract" {
  description = "gcp-projects stage contract: environment_config (environment => folder_id, host_project_id, host_project_number, region, cidr_block, labels, is_production, vpc_sc_access_policy_id); must contain var.environment. Null = gcp.contracts.projects from config/landing-zone.yaml, else read from the gcp-projects workspace's remote state."
  type = object({
    environment_config = map(object({
      folder_id               = string
      host_project_id         = string
      host_project_number     = string
      region                  = string
      cidr_block              = string
      labels                  = optional(map(string), {})
      is_production           = optional(bool)
      vpc_sc_access_policy_id = optional(string)
    }))
  })
  default = null
}

variable "network_hub_contract" {
  description = "gcp-network-hub stage contract: hub_network {vpc_self_link, dns_domain} the env VPC peers with and forwards DNS to. Null = gcp.contracts.network_hub from config/landing-zone.yaml, else read from the gcp-network-hub workspace's remote state. Ignored when enable_network_hub = false."
  type = object({
    vpc_self_link = string
    dns_domain    = string
  })
  default = null

  validation {
    condition     = var.network_hub_contract == null || endswith(try(var.network_hub_contract.dns_domain, ""), ".")
    error_message = "network_hub_contract.dns_domain must be a fully-qualified DNS name ending in a dot (e.g. hub.internal.)."
  }
}

variable "enable_network_hub" {
  description = "Connect the environment VPC to the gcp-network-hub (VPC peering + DNS peering zone, from network_hub_contract or the gcp-network-hub remote state). False = standalone: no gcp-network-hub read, no hub peering, no DNS peering zone."
  type        = bool
  default     = true
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
  description = "Enable the environment Cloud Armor security policy (also implied by public ingress). Null = a configured preset (e.g. prod-gcp-workload), else false."
  type        = bool
  default     = null
}

variable "enable_owasp_rules" {
  description = "Enable Cloud Armor OWASP managed rules. Null = a configured preset (e.g. prod-gcp-workload), else false."
  type        = bool
  default     = null
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
    Null = a configured preset (e.g. prod-gcp-workload sets false), else true.
  EOT
  type        = bool
  default     = null

  validation {
    # Guards the preset loader (config.tf). Hosted here because a validation on
    # landing_zone_config_path would cycle; the var reference is a no-op.
    condition     = (var.vpc_sc_enable_dry_run == null || var.vpc_sc_enable_dry_run != null) && length(setsubtract(keys(local.preset), local.preset_supported_keys)) == 0
    error_message = "A preset for envs/gcp/workload sets a key this root cannot take from a preset (supported: vpc_sc_enable_dry_run, enable_cloud_armor, enable_owasp_rules). Set it as a variable instead."
  }
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

variable "enable_artifact_registry_vulnerability_scanning" {
  description = "Scan app-service container images on push (Container Scanning API + repository vulnerability scanning INHERITED). Billed per scanned image. Default true."
  type        = bool
  default     = true
}

# --- VM backup + OS patching (BCK-05, VUL-05) ---------------------------------

variable "enable_vm_backup_policy" {
  description = "Create a Compute Engine snapshot-schedule resource policy in the host project and each service-team project (modules/gcp/backup/backup-plan). Free until a disk is attached to it. Default true."
  type        = bool
  default     = true
}

variable "vm_backup_schedules" {
  description = "Snapshot schedules passed to modules/gcp/backup/backup-plan (see its `schedules` input for the shape). Null = one \"vm-daily-snapshots\" policy: daily at 04:00 UTC, 30-day retention, snapshots kept if the disk is deleted."
  type        = any
  default     = null
}

variable "enable_os_patch_management" {
  description = "Create a weekly VM Manager patch deployment (and enable osconfig.googleapis.com) in the host project and each service-team project (modules/gcp/ops/os-config). Harmless with no VMs. The workload apply SA receives roles/osconfig.patchDeploymentAdmin via the gcp-bootstrap workload_folder_roles allow-list."
  type        = bool
  default     = true
}

variable "os_patch_deployments" {
  description = "Patch deployments passed to modules/gcp/ops/os-config (see its `patch_deployments` input for the shape). Null = one \"weekly-os-patch\" deployment: every VM in the project, Sundays 03:00 UTC, default reboot behaviour."
  type        = any
  default     = null
}

# -----------------------------------------------------------------------------
# Public ingress (modules/gcp/network/app-ingress) + first-revision image
# -----------------------------------------------------------------------------

variable "app_bootstrap_image" {
  description = "Image the first Cloud Run revision of an app service runs when its `image` is unset. The public sample (us-docker.pkg.dev/cloudrun/container/hello) is blocked by a VPC-SC perimeter restricting artifactregistry.googleapis.com and by Binary Authorization; mirror a placeholder inside the perimeter and point this at it. Null = gcp.workload.bootstrap_image from config/landing-zone.yaml, else the public sample."
  type        = string
  default     = null
}

variable "enable_public_ingress" {
  description = "Expose the public_ingress_services through a global external Application Load Balancer each (serverless NEG + Cloud Armor policy + Google-managed certificate for their domains). Null = on when public_ingress_services (or gcp.workload.public_ingress.<environment> in config/landing-zone.yaml) is non-empty."
  type        = bool
  default     = null
}

variable "public_ingress_services" {
  description = "app_services entries to expose publicly, keyed by service name: domains (FQDNs the managed certificate covers; point DNS at the output IP, or set dns_managed_zone to a Cloud DNS zone in the host project to create the A records), enable_cdn. Each exposed service is switched to ingress INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER with unauthenticated invocation unless its app_services entry sets them. Null = gcp.workload.public_ingress.<environment> from config/landing-zone.yaml."
  type = map(object({
    domains          = list(string)
    dns_managed_zone = optional(string)
    enable_cdn       = optional(bool, false)
  }))
  default = null

  validation {
    condition = alltrue([
      for k in keys(var.public_ingress_services != null ? var.public_ingress_services : try(local.cfg.public_ingress[var.environment], {})) :
      contains(keys(var.app_services), k)
    ])
    error_message = "Every public_ingress_services (or gcp.workload.public_ingress.<environment>) key must be an app_services entry."
  }
}

variable "private_service_connect_target" {
  description = "PSC endpoint bundle for Google APIs: all-apis or vpc-sc. Null (default) derives it: vpc-sc once the environment's VPC-SC perimeter is enforced, else all-apis."
  type        = string
  default     = null

  validation {
    condition     = var.private_service_connect_target == null || contains(["all-apis", "vpc-sc"], coalesce(var.private_service_connect_target, "all-apis"))
    error_message = "private_service_connect_target must be all-apis or vpc-sc."
  }
}
