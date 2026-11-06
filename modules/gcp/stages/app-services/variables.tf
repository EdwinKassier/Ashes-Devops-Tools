/**
 * Copyright 2026 Ashes
 *
 * App Services Stage - Variables
 */

# -----------------------------------------------------------------------------
# PLACEMENT (from the env host project / host stage)
# -----------------------------------------------------------------------------

variable "project_id" {
  description = "The environment host project ID. Every app resource (registry, service accounts, Cloud Run, Cloud SQL, WIF pool, GKE) is created here."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be 6-30 characters, start with a lowercase letter, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "project_number" {
  description = "Numeric project number of var.project_id. Used to build the deterministic Workload Identity pool resource name (principalSet members need the number, not the ID). Required when enable_app_deploy_wif = true."
  type        = string
  default     = null

  validation {
    condition     = var.project_number == null || can(regex("^[0-9]+$", var.project_number))
    error_message = "project_number must be the numeric GCP project number."
  }

  validation {
    condition     = !var.enable_app_deploy_wif || var.project_number != null
    error_message = "project_number is required when enable_app_deploy_wif = true."
  }
}

variable "region" {
  description = "Region for the Artifact Registry repositories, Cloud Run services, Cloud SQL instances and the GKE cluster (the environment region)."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a valid GCP region (e.g. \"europe-west1\")."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod, ...). Used in default names and labels."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,29}$", var.environment))
    error_message = "environment must be lowercase alphanumeric with optional hyphens."
  }
}

variable "network_id" {
  description = "ID of the environment Shared VPC network (projects/<p>/global/networks/<n>). Cloud SQL peers into it via the host stage's Private Service Access; Cloud Run and GKE attach to it. Required when any service or GKE is declared."
  type        = string
  default     = null

  validation {
    condition     = (length(var.services) == 0 && !var.enable_gke_autopilot) || var.network_id != null
    error_message = "network_id is required when services are declared or enable_gke_autopilot = true."
  }
}

variable "subnetwork_id" {
  description = "ID of the default Shared VPC subnet (projects/<p>/regions/<r>/subnetworks/<s>) used for Cloud Run Direct VPC egress and GKE nodes. Per-service `subnetwork_id` overrides it for Cloud Run."
  type        = string
  default     = null

  validation {
    condition = alltrue([
      for k, s in var.services : s.subnetwork_id != null || var.subnetwork_id != null
    ]) && (!var.enable_gke_autopilot || var.subnetwork_id != null)
    error_message = "subnetwork_id (or a per-service subnetwork_id) is required for every service, and for GKE."
  }
}

variable "labels" {
  description = "Labels applied to every labelable resource."
  type        = map(string)
  default     = {}
}

variable "enable_deletion_protection" {
  description = "Default deletion protection for Cloud Run services, Cloud SQL instances and the GKE cluster. Per-service `enable_deletion_protection` / `database.enable_deletion_protection` override it."
  type        = bool
  default     = true
}

variable "enable_project_services" {
  description = "Enable the Google APIs the declared resources need (run, artifactregistry, sqladmin, secretmanager, iamcredentials, sts, container) on the host project. Only APIs for features actually in use are enabled; disable_on_destroy is false."
  type        = bool
  default     = true
}

variable "enable_vulnerability_scanning" {
  description = "Scan every service's container images automatically on push (Artifact Analysis): enables containerscanning.googleapis.com (with enable_project_services) and sets each repository's vulnerability scanning to INHERITED. Billed per scanned image. Default true."
  type        = bool
  default     = true
}

variable "enable_on_demand_scanning" {
  description = "Also enable ondemandscanning.googleapis.com so CI can scan images before pushing (`gcloud artifacts docker images scan`). Default false."
  type        = bool
  default     = false
}

variable "artifact_registry_kms_key_name" {
  description = "Optional CMEK (projects/<p>/locations/<l>/keyRings/<r>/cryptoKeys/<k>) for every service's Artifact Registry repository. Null uses Google-managed encryption. The Artifact Registry service agent needs roles/cloudkms.cryptoKeyEncrypterDecrypter on the key first."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# DEPLOY IDENTITY (GitHub Actions -> Workload Identity Federation)
# -----------------------------------------------------------------------------

variable "enable_app_deploy_wif" {
  description = "Create a Workload Identity pool for APPLICATION deploys in the host project (separate from the infra pool in gcp-bootstrap), with one GitHub OIDC provider. Required for any service that sets `github`."
  type        = bool
  default     = false
}

variable "app_deploy_wif_pool_id" {
  description = "ID of the app-deploy Workload Identity pool. Null defaults to \"apps-<environment>\" (truncated to 32 chars). Pool IDs stay reserved for 30 days after deletion."
  type        = string
  default     = null

  validation {
    condition     = var.app_deploy_wif_pool_id == null || can(regex("^[a-z][a-z0-9-]{2,30}[a-z0-9]$", var.app_deploy_wif_pool_id))
    error_message = "app_deploy_wif_pool_id must be 4-32 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "github_repository_owner_id" {
  description = "Optional IMMUTABLE numeric GitHub organization/user ID. When set, the provider additionally rejects any token whose repository_owner_id differs (defence in depth on top of the per-repository_id condition)."
  type        = string
  default     = null

  validation {
    condition     = var.github_repository_owner_id == null || can(regex("^[0-9]+$", var.github_repository_owner_id))
    error_message = "github_repository_owner_id must be the numeric GitHub owner ID (not the org name)."
  }
}

# -----------------------------------------------------------------------------
# SERVICES
# -----------------------------------------------------------------------------

variable "bootstrap_image" {
  description = "Image the FIRST Cloud Run revision of a service runs when its `image` is null (CI deploys replace it). The default, Google's public sample us-docker.pkg.dev/cloudrun/container/hello, lives OUTSIDE your project: a VPC-SC perimeter that restricts artifactregistry.googleapis.com, or a Binary Authorization policy, blocks it. In that case mirror a placeholder into a repo inside the perimeter (e.g. <region>-docker.pkg.dev/<host-project>/<repo>/hello:bootstrap) and set this (gcp.workload.bootstrap_image in config/landing-zone.yaml)."
  type        = string
  default     = "us-docker.pkg.dev/cloudrun/container/hello"

  validation {
    condition     = length(trimspace(var.bootstrap_image)) > 0 && !can(regex("\\s", var.bootstrap_image))
    error_message = "bootstrap_image must be a non-empty image reference without whitespace."
  }
}

variable "services" {
  description = <<-EOT
    Application services, keyed by service name (2-22 chars: lowercase letters,
    digits, hyphens). Each entry creates, in the host project: an Artifact
    Registry docker repo `<name>`, a runtime SA `<name>-run`, and a Cloud Run v2
    service `<name>` (internal ingress, Direct VPC egress, scale-to-zero).
    Optional per entry:
      database = {...}  -> private-IP Cloud SQL Postgres `<name>-db` with IAM auth;
                           the runtime SA is its IAM database user.
      github   = {...}  -> deploy SA `<name>-deploy` bound via WIF to the GitHub
                           repo's IMMUTABLE numeric repository_id (optionally a
                           ref and/or GitHub environment). Needs enable_app_deploy_wif.
      secrets  = { ENV_VAR = { secret = "<secret id in the host project>" } }
                           -> env vars from Secret Manager; the runtime SA gets
                           secretAccessor on exactly those secrets.
    The default `{}` creates nothing.
  EOT
  type = map(object({
    image                       = optional(string) # null => var.bootstrap_image
    ingress                     = optional(string, "INGRESS_TRAFFIC_INTERNAL_ONLY")
    cpu                         = optional(string, "1000m")
    memory                      = optional(string, "512Mi")
    min_instances               = optional(number, 0)
    max_instances               = optional(number, 10)
    concurrency                 = optional(number, 80)
    timeout                     = optional(string, "300s")
    env_vars                    = optional(map(string), {})
    secrets                     = optional(map(object({ secret = string, version = optional(string, "latest") })), {})
    subnetwork_id               = optional(string)
    vpc_egress                  = optional(string, "PRIVATE_RANGES_ONLY")
    enable_binary_authorization = optional(bool, false)
    binary_authorization_policy = optional(string)
    enable_unauthenticated      = optional(bool, false)
    invoker_members             = optional(list(string), [])
    runtime_project_roles       = optional(list(string), [])
    enable_deletion_protection  = optional(bool)
    labels                      = optional(map(string), {})

    artifact_registry = optional(object({
      immutable_tags             = optional(bool, true)
      keep_count                 = optional(number, 20)
      delete_untagged_older_than = optional(string, "604800s")
      cleanup_policy_dry_run     = optional(bool, false)
    }), {})

    database = optional(object({
      database_version              = optional(string, "POSTGRES_16")
      edition                       = optional(string, "ENTERPRISE")
      tier                          = optional(string, "db-custom-1-3840")
      databases                     = optional(list(string), ["app"])
      enable_high_availability      = optional(bool, false)
      enable_point_in_time_recovery = optional(bool, true)
      encryption_key_name           = optional(string)
      enable_deletion_protection    = optional(bool)
    }))

    github = optional(object({
      repository_id = string
      repository    = optional(string)
      ref           = optional(string)
      environment   = optional(string)
    }))
  }))
  default = {}

  validation {
    condition     = alltrue([for k, s in var.services : can(regex("^[a-z][a-z0-9-]{0,20}[a-z0-9]$", k))])
    error_message = "service keys must be 2-22 characters: lowercase letters, digits and hyphens, starting with a letter (the key prefixes the <name>-run / <name>-deploy service account IDs)."
  }

  validation {
    condition = alltrue([for k, s in var.services : contains([
      "INGRESS_TRAFFIC_ALL", "INGRESS_TRAFFIC_INTERNAL_ONLY", "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER",
    ], s.ingress)])
    error_message = "services[*].ingress must be INGRESS_TRAFFIC_ALL, INGRESS_TRAFFIC_INTERNAL_ONLY or INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER."
  }

  validation {
    condition     = alltrue([for k, s in var.services : contains(["ALL_TRAFFIC", "PRIVATE_RANGES_ONLY"], s.vpc_egress)])
    error_message = "services[*].vpc_egress must be ALL_TRAFFIC or PRIVATE_RANGES_ONLY."
  }

  validation {
    condition     = alltrue([for k, s in var.services : s.github == null || can(regex("^[0-9]+$", s.github.repository_id))])
    error_message = "services[*].github.repository_id must be the IMMUTABLE numeric GitHub repository ID (gh api repos/<owner>/<repo> --jq .id), not the owner/name."
  }

  validation {
    condition     = alltrue([for k, s in var.services : s.github == null || try(s.github.ref, null) == null || can(regex("^refs/(heads|tags)/", s.github.ref))])
    error_message = "services[*].github.ref must be a full git ref (refs/heads/<branch> or refs/tags/<tag>)."
  }

  validation {
    condition     = alltrue([for k, s in var.services : !s.enable_unauthenticated || s.ingress == "INGRESS_TRAFFIC_ALL" || s.ingress == "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"])
    error_message = "enable_unauthenticated only makes sense with INGRESS_TRAFFIC_ALL or INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER (front door) ingress."
  }

  validation {
    condition     = var.enable_app_deploy_wif || alltrue([for k, s in var.services : s.github == null])
    error_message = "a service sets `github` (a deploy identity) but enable_app_deploy_wif = false. Enable the app-deploy WIF pool."
  }
}

# -----------------------------------------------------------------------------
# GKE AUTOPILOT (optional, env level)
# -----------------------------------------------------------------------------

variable "enable_gke_autopilot" {
  description = "Create one private GKE Autopilot cluster for the environment on var.subnetwork_id. Default off."
  type        = bool
  default     = false
}

variable "gke_cluster_name" {
  description = "Name of the GKE Autopilot cluster. Null defaults to \"<environment>-apps\"."
  type        = string
  default     = null
}

variable "gke_master_ipv4_cidr_block" {
  description = "The /28 control-plane CIDR for the GKE cluster. Must not overlap any range in the VPC or its peers."
  type        = string
  default     = "172.16.0.0/28"
}

variable "gke_cluster_secondary_range_name" {
  description = "Subnet secondary range name for pod IPs. Null lets GKE allocate one."
  type        = string
  default     = null
}

variable "gke_services_secondary_range_name" {
  description = "Subnet secondary range name for Service IPs. Null lets GKE allocate one."
  type        = string
  default     = null
}

variable "gke_master_authorized_networks" {
  description = "CIDR blocks allowed to reach the GKE control plane."
  type = list(object({
    cidr_block   = string
    display_name = optional(string)
  }))
  default = []
}
