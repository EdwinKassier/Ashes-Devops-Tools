/**
 * Copyright 2026 Ashes
 *
 * Environment Stage - Variables
 */

# --- Identity and upstream contract values -----------------------------------

variable "environment" {
  description = "Application environment name (e.g. dev, staging, prod). Names the VPC, the perimeter, the flow-log dataset and the ingress load balancers."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,29}$", var.environment))
    error_message = "environment must be lowercase alphanumeric with optional hyphens (e.g., 'dev', 'staging', 'prod')."
  }
}

variable "project_prefix" {
  description = "Landing-zone name prefix (org.prefix). Names the VPC (<prefix>-<environment>-vpc) and the budget."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.project_prefix))
    error_message = "project_prefix must start with a lowercase letter and contain only lowercase letters, digits, and hyphens."
  }
}

variable "org_id" {
  description = "Bare numeric organization ID (the gcp-organization contract org_id)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.org_id))
    error_message = "org_id must be the bare numeric organization ID (no organizations/ prefix)."
  }
}

variable "billing_account" {
  description = "Billing account for the budget and the service-team projects, bare (XXXXXX-XXXXXX-XXXXXX) or billingAccounts/ form (the gcp-organization contract billing_account)."
  type        = string
}

# tflint-ignore: terraform_unused_declarations # deprecated and ignored, kept so a set value warns until v1.0
variable "admin_project_number" {
  description = "Ignored. The perimeter has no default ingress rule any more, so the stage no longer needs the admin project number."
  type        = string
  default     = null
  deprecated  = "Ignored: the perimeter has no default ingress rule. Remove this input; it is deleted in v1.0."
}

variable "is_production" {
  description = "Whether this is a production environment (the gcp-projects environment_config is_production). Production turns Cloud SQL high availability on by default and, unless enable_host_project_workloads is set, requires every app service to name a service_team."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_host_project_workloads" {
  description = "Allow app services without a service_team, which then run in the Shared VPC host project next to the network core. Null (default) = allowed outside production, refused in production. Set true to allow it in production too, false to refuse it everywhere."
  type        = bool
  default     = null

  validation {
    condition = coalesce(var.enable_host_project_workloads, !var.is_production) || alltrue([
      for k, s in var.app_services : try(s.service_team, null) != null
    ])
    error_message = "app_services ${join(", ", [for k, s in var.app_services : k if try(s.service_team, null) == null])} set no service_team, so they would run in the Shared VPC host project. Give each a service_teams key (its own service project). Host-project workloads are refused in production by default; set enable_host_project_workloads = true to allow them explicitly."
  }
}

variable "host_project" {
  description = "The environment's Shared VPC host project, from the gcp-projects contract environment_config[<environment>]: project_id, project_number, folder_id (folders/NNN or bare), region and the VPC cidr_block."
  type = object({
    project_id     = string
    project_number = string
    folder_id      = string
    region         = string
    cidr_block     = string
  })

  validation {
    condition     = can(cidrhost(var.host_project.cidr_block, 0))
    error_message = "host_project.cidr_block must be a valid IPv4 CIDR block."
  }
}

variable "labels" {
  description = "Labels applied to every resource the environment creates."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "deletion_protection" {
  description = "Deletion protection for the network core, Cloud SQL and the GKE cluster."
  type        = bool
  default     = true
  nullable    = false
}

# --- Network --------------------------------------------------------------------

variable "network" {
  description = "Spoke VPC settings: flow_logs (aggregation_interval, sampling 0.0-1.0), flow_logs_retention_days for the BigQuery export, private_service_connect_target (all-apis | vpc-sc; null derives vpc-sc once the perimeter is enforced, else all-apis), and additional_regions: opt-in extra regions of the spoke VPC keyed by region name (subnet_cidrs public/private/database, optional secondary_ranges, nat default true for a Cloud Router and NAT in the region; empty = single-region)."
  type = object({
    flow_logs = optional(object({
      aggregation_interval = optional(string, "INTERVAL_5_SEC")
      sampling             = optional(number, 0.1)
    }), {})
    flow_logs_retention_days       = optional(number, 30)
    private_service_connect_target = optional(string)
    additional_regions = optional(map(object({
      subnet_cidrs = object({
        public   = string
        private  = string
        database = string
      })
      secondary_ranges = optional(list(object({
        range_name    = string
        ip_cidr_range = string
      })), [])
      nat = optional(bool, true)
    })), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.network.flow_logs.sampling >= 0 && var.network.flow_logs.sampling <= 1
    error_message = "network.flow_logs.sampling must be between 0.0 and 1.0."
  }

  validation {
    condition     = var.network.private_service_connect_target == null || contains(["all-apis", "vpc-sc"], coalesce(var.network.private_service_connect_target, "all-apis"))
    error_message = "network.private_service_connect_target must be all-apis or vpc-sc."
  }
}

variable "hub" {
  description = "Hub connectivity resolved from the gcp-network-hub contract: connectivity (peering | ncc), ncc (hub_id, group), the hub VPC peerings, the DNS peering zones, and the opt-in egress proxy (preview): egress_proxy.enabled with the hub Secure Web Proxy's service_attachment. Empty maps = standalone (no hub)."
  type = object({
    connectivity = optional(string, "peering")
    egress_proxy = optional(object({
      enabled            = optional(bool, false)
      service_attachment = optional(string)
      global_access      = optional(bool, false)
    }), {})
    ncc = optional(object({
      hub_id = optional(string)
      group  = optional(string, "edge")
    }), {})
    peerings = optional(map(object({
      peer_network           = string
      create_reverse_peering = optional(bool, true)
      export_custom_routes   = optional(bool, false)
      import_custom_routes   = optional(bool, false)
    })), {})
    dns_zones = optional(map(object({
      dns_name        = string
      visibility      = string
      description     = optional(string)
      dnssec_enabled  = optional(bool, false)
      peering_network = optional(string)
    })), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["peering", "ncc"], var.hub.connectivity)
    error_message = "hub.connectivity must be peering or ncc."
  }
}

variable "cloud_armor" {
  description = "Environment Cloud Armor policy: enabled, owasp_rules, adaptive_protection, owasp_sensitivity (1 strictest to 4). Public ingress attaches it to every backend, so the caller enables it whenever ingress is on."
  type = object({
    enabled             = optional(bool, false)
    owasp_rules         = optional(bool, false)
    adaptive_protection = optional(bool, false)
    owasp_sensitivity   = optional(number, 2)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains([1, 2, 3, 4], var.cloud_armor.owasp_sensitivity)
    error_message = "cloud_armor.owasp_sensitivity must be 1, 2, 3, or 4."
  }
}

variable "vpc_service_controls" {
  description = <<-EOT
    The environment VPC-SC perimeter. access_policy_name null = no perimeter.
    perimeter_title null = "<ENVIRONMENT> Perimeter". enable_dry_run keeps the
    perimeter in dry-run; dry_run_restricted_services stages a dry-run delta on
    an enforced perimeter. ingress_policies / egress_policies are used as given;
    empty (default) = no rule, so an enforced perimeter admits nothing across
    its edge until the operator names identities and projects. An ingress
    source.resource must be projects/<number> or a VPC network
    (//compute.googleapis.com/projects/<p>/global/networks/<n>); use
    access_level "*" for callers from outside Google Cloud (CI, TFC). An egress
    rule may not combine identity_type ANY_IDENTITY with resources "*".
  EOT
  type = object({
    access_policy_name = optional(string)
    perimeter_title    = optional(string)
    enable_dry_run     = optional(bool, true)
    restricted_services = optional(list(string), [
      "bigquery.googleapis.com",
      "storage.googleapis.com",
      "secretmanager.googleapis.com",
      "cloudkms.googleapis.com",
      "pubsub.googleapis.com",
      "sqladmin.googleapis.com",
      "container.googleapis.com",
      "artifactregistry.googleapis.com",
    ])
    dry_run_restricted_services = optional(list(string))
    ingress_policies = optional(list(object({
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
    })), [])
    egress_policies = optional(list(object({
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
    })), [])
  })
  default  = {}
  nullable = false

  # A Workload Identity pool (or any non-project, non-network name) is not a
  # valid ingress source: the API rejects it, or it never matches a request.
  validation {
    condition = alltrue(flatten([
      for p in var.vpc_service_controls.ingress_policies : [
        for src in(p.sources == null ? [] : p.sources) : src.resource == null || can(regex("^(projects/[0-9]+|//compute[.]googleapis[.]com/projects/[^/]+/global/networks/[^/]+)$", coalesce(src.resource, "-")))
      ]
    ]))
    error_message = "vpc_service_controls.ingress_policies[*].sources[*].resource must be projects/<number> or //compute.googleapis.com/projects/<project>/global/networks/<network>. For callers outside Google Cloud use access_level = \"*\" and name them in identities."
  }

  # Any identity to any project anywhere is the copy-out path the perimeter
  # exists to close.
  validation {
    condition = !anytrue([
      for p in var.vpc_service_controls.egress_policies : p.identity_type == "ANY_IDENTITY" && p.resources != null && contains(coalesce(p.resources, ["-"]), "*")
    ])
    error_message = "vpc_service_controls.egress_policies may not combine identity_type = \"ANY_IDENTITY\" with resources = [\"*\"]: that lets any identity copy data to any project. Name the identities and the target projects (projects/<number>)."
  }
}

# --- Budget ---------------------------------------------------------------------

variable "budget" {
  description = "Environment budget: monthly_limit in currency (0 = no budget, topic or notifier) and the ISO 4217 currency."
  type = object({
    monthly_limit = optional(number, 0)
    currency      = optional(string, "USD")
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.budget.monthly_limit >= 0
    error_message = "budget.monthly_limit must be >= 0 (0 disables the budget)."
  }

  validation {
    condition     = can(regex("^[A-Z]{3}$", var.budget.currency))
    error_message = "budget.currency must be a 3-letter ISO 4217 currency code (e.g., USD, EUR)."
  }
}

# --- Service teams ----------------------------------------------------------------

variable "service_teams" {
  description = "Service team registry: one stages/workload service project per entry, in the environment folder and attached to the Shared VPC. Fields as in envs/gcp/workload var.service_teams."
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
  default  = {}
  nullable = false

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

# --- VM operations ----------------------------------------------------------------

variable "vm_operations" {
  description = "VM backup and patching in the host project and every service-team project: enable_backup_policy with backup_schedules (modules/gcp/backup/backup-plan `schedules`; null = one daily vm-daily-snapshots policy), enable_os_patch_management with os_patch_deployments (modules/gcp/ops/os-config `patch_deployments`; null = one weekly-os-patch deployment)."
  type = object({
    enable_backup_policy       = optional(bool, true)
    backup_schedules           = optional(any)
    enable_os_patch_management = optional(bool, true)
    os_patch_deployments       = optional(any)
  })
  default  = {}
  nullable = false
}

# --- SaaS secret bridge -------------------------------------------------------------

variable "saas_secret_bridge" {
  description = "Opt-in Secret Manager secret in the host project holding saas_secret_bridge_value: enabled, secret_name, accessor_members (prefixed IAM members) and value_version (the write-only version counter; bump it to re-write the value)."
  type = object({
    enabled          = optional(bool, false)
    secret_name      = optional(string, "supabase-connection")
    accessor_members = optional(list(string), [])
    value_version    = optional(number, 1)
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for m in var.saas_secret_bridge.accessor_members : can(regex("^(serviceAccount|user|group):", m))])
    error_message = "Each saas_secret_bridge.accessor_members entry must be a prefixed IAM member (serviceAccount:, user:, or group:)."
  }
}

variable "saas_secret_bridge_value" {
  description = "The bridged connection payload (JSON) written write-only into the saas_secret_bridge secret. Ephemeral: pass it from an ephemeral resource (the workload root reads it with ephemeral tfe_outputs) or a plain value; it is never stored in plan or state. Required when saas_secret_bridge.enabled."
  type        = string
  default     = null
  sensitive   = true
  ephemeral   = true

  validation {
    condition     = !var.saas_secret_bridge.enabled || var.saas_secret_bridge_value != null
    error_message = "saas_secret_bridge_value is required when saas_secret_bridge.enabled = true."
  }
}

# --- Application golden path ------------------------------------------------------

variable "app_services" {
  description = "Application services keyed by service name, in the shape of the modules/gcp/stages/app-services `services` input (which validates them). `service_team = \"<key>\"` deploys a service into that service team's project. Services named in public_ingress default to LB-only ingress with unauthenticated invocation. A key that the services shape does not have fails the plan."
  # Deliberately untyped: an object type constraint silently drops attributes it
  # does not declare, so a misspelled key would vanish without an error, and
  # unset optional attributes would arrive as null and override the
  # public_ingress defaults merged in main.tf. The validation below rejects
  # unknown keys instead; the app-services stage types and validates values.
  type     = any
  default  = {}
  nullable = false

  validation {
    condition = length([for k in flatten([
      for name, s in var.app_services : concat(
        [for k in keys(s) : "${name}.${k}" if !contains(["service_team", "runtime", "image", "ingress", "cpu", "memory", "min_instances", "max_instances", "concurrency", "timeout", "env_vars", "secrets", "subnetwork_id", "vpc_egress", "enable_binary_authorization", "binary_authorization_policy", "enable_unauthenticated", "invoker_members", "runtime_project_roles", "enable_deletion_protection", "labels", "project_id", "project_number", "grant_network_access", "network_access_group", "artifact_registry", "database", "github", "alerts", "job", "slo", "pubsub"], k)],
        flatten([
          for sub, allowed in {
            artifact_registry = ["immutable_tags", "keep_count", "delete_untagged_older_than", "cleanup_policy_dry_run"]
            database          = ["database_version", "edition", "tier", "databases", "enable_high_availability", "enable_point_in_time_recovery", "backup_location", "encryption_key_name", "enable_deletion_protection"]
            github            = ["repository_id", "repository", "ref", "environment"]
            alerts            = ["enabled", "error_ratio_threshold", "p99_latency_ms", "duration"]
            job               = ["task_count", "parallelism", "max_retries"]
            slo               = ["sli_type", "goal", "rolling_period_days", "latency_threshold", "enable_burn_rate_alert", "burn_rate_threshold", "burn_rate_lookback"]
            pubsub            = ["enabled", "ack_deadline_seconds", "max_delivery_attempts", "message_retention_duration"]
          } : [for k in try(keys(s[sub]), []) : "${name}.${sub}.${k}" if !contains(allowed, k)]
        ]),
        flatten([for sk, sv in try(s.secrets, {}) : [for k in try(keys(sv), []) : "${name}.secrets.${sk}.${k}" if !contains(["secret", "version"], k)]]),
      )
    ]) : k]) == 0
    error_message = "app_services has keys the services shape does not have (misspelled or unsupported): ${join(", ", [for k in flatten([
      for name, s in var.app_services : concat(
        [for k in keys(s) : "${name}.${k}" if !contains(["service_team", "runtime", "image", "ingress", "cpu", "memory", "min_instances", "max_instances", "concurrency", "timeout", "env_vars", "secrets", "subnetwork_id", "vpc_egress", "enable_binary_authorization", "binary_authorization_policy", "enable_unauthenticated", "invoker_members", "runtime_project_roles", "enable_deletion_protection", "labels", "project_id", "project_number", "grant_network_access", "network_access_group", "artifact_registry", "database", "github", "alerts", "job", "slo", "pubsub"], k)],
        flatten([
          for sub, allowed in {
            artifact_registry = ["immutable_tags", "keep_count", "delete_untagged_older_than", "cleanup_policy_dry_run"]
            database          = ["database_version", "edition", "tier", "databases", "enable_high_availability", "enable_point_in_time_recovery", "backup_location", "encryption_key_name", "enable_deletion_protection"]
            github            = ["repository_id", "repository", "ref", "environment"]
            alerts            = ["enabled", "error_ratio_threshold", "p99_latency_ms", "duration"]
            job               = ["task_count", "parallelism", "max_retries"]
            slo               = ["sli_type", "goal", "rolling_period_days", "latency_threshold", "enable_burn_rate_alert", "burn_rate_threshold", "burn_rate_lookback"]
            pubsub            = ["enabled", "ack_deadline_seconds", "max_delivery_attempts", "message_retention_duration"]
          } : [for k in try(keys(s[sub]), []) : "${name}.${sub}.${k}" if !contains(allowed, k)]
        ]),
        flatten([for sk, sv in try(s.secrets, {}) : [for k in try(keys(sv), []) : "${name}.secrets.${sk}.${k}" if !contains(["secret", "version"], k)]]),
      )
    ]) : k])}."
  }
}

variable "public_ingress" {
  description = "app_services entries to expose through a global external Application Load Balancer each, keyed by service name: domains, optional dns_managed_zone (Cloud DNS zone in the host project for the A records), enable_cdn. Empty = no public ingress."
  type = map(object({
    domains          = list(string)
    dns_managed_zone = optional(string)
    enable_cdn       = optional(bool, false)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k in keys(var.public_ingress) : contains(keys(var.app_services), k)])
    error_message = "Every public_ingress key must be an app_services entry."
  }
}

variable "app_platform" {
  description = "Settings shared by every app service: subnetwork_id (null = the first private subnet), bootstrap_image (first revision), artifact_registry_kms_key_name, enable_vulnerability_scanning, the app-deploy WIF pool (enable_deploy_wif, deploy_wif_pool_id, github_repository_owner_id), alerts (enable_alerts, alert_notification_channel_ids) and the optional GKE Autopilot cluster (gke)."
  type = object({
    subnetwork_id                  = optional(string)
    bootstrap_image                = optional(string, "us-docker.pkg.dev/cloudrun/container/hello")
    artifact_registry_kms_key_name = optional(string)
    enable_vulnerability_scanning  = optional(bool, true)
    enable_deploy_wif              = optional(bool, false)
    deploy_wif_pool_id             = optional(string)
    github_repository_owner_id     = optional(string)
    enable_alerts                  = optional(bool, true)
    alert_notification_channel_ids = optional(list(string), [])
    gke = optional(object({
      enabled                = optional(bool, false)
      master_ipv4_cidr_block = optional(string, "172.16.0.0/28")
      master_authorized_networks = optional(list(object({
        cidr_block   = string
        display_name = optional(string)
      })), [])
      cluster_secondary_range_name  = optional(string)
      services_secondary_range_name = optional(string)
    }), {})
  })
  default  = {}
  nullable = false
}
