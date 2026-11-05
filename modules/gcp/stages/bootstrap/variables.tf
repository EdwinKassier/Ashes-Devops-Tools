variable "project_prefix" {
  description = <<-EOT
    Short prefix prepended to all project names created by this bootstrap.
    Constraints: 1–10 characters, starts with a lowercase letter, may contain
    lowercase letters, digits, and hyphens. Kept short so the full project ID
    stays within GCP's 30-character limit after suffixes are appended.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,9}$", var.project_prefix))
    error_message = "project_prefix must start with a lowercase letter, contain only lowercase letters, digits, and hyphens, and be at most 10 characters long."
  }
}

variable "org_id" {
  description = "Numeric GCP Organization ID (digits only, without the 'organizations/' prefix)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.org_id))
    error_message = "org_id must be a numeric organization ID (digits only, without 'organizations/' prefix)."
  }
}

variable "billing_account" {
  description = "Billing Account ID in format XXXXXX-XXXXXX-XXXXXX"
  type        = string

  validation {
    condition     = can(regex("^[A-Z0-9]{6}-[A-Z0-9]{6}-[A-Z0-9]{6}$", var.billing_account))
    error_message = "billing_account must be a valid GCP billing account ID in format XXXXXX-XXXXXX-XXXXXX (uppercase alphanumeric groups separated by hyphens)."
  }
}

variable "admin_email" {
  description = "Email address for the organization administrator"
  type        = string

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.admin_email))
    error_message = "admin_email must be a valid email address."
  }
}

variable "github_org" {
  description = "GitHub organization (owner) name. Only used when enable_github_wif = true (the trust itself keys on github_repository_owner_id, not this mutable name)."
  type        = string
  default     = null

  validation {
    condition     = var.github_org == null || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]*$", var.github_org))
    error_message = "github_org must contain only alphanumeric characters and hyphens, starting with an alphanumeric character."
  }
}

variable "github_repo" {
  description = "GitHub repository name (without owner prefix). Only used when enable_github_wif = true (the trust itself keys on github_repository_id, not this mutable name)."
  type        = string
  default     = null

  validation {
    condition     = var.github_repo == null || can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]*$", var.github_repo))
    error_message = "github_repo must contain only alphanumeric characters, hyphens, underscores, and dots, starting with an alphanumeric character."
  }
}

variable "enable_github_wif" {
  description = "Create the GitHub Actions WIF pool. Default false: no workflow in this repo uses GCP OIDC, so a standing trust is unused privilege (audit C2). When true, the trust is pinned to github_repository_id + github_repository_owner_id on refs/heads/main and bound ONLY to the read-only organization plan SA."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_github_wif || (var.github_org != null && var.github_repo != null && var.github_repository_id != null && var.github_repository_owner_id != null)
    error_message = "enable_github_wif = true requires github_org, github_repo, github_repository_id and github_repository_owner_id (the immutable numeric IDs from the GitHub API: GET /repos/<owner>/<repo> -> .id and .owner.id)."
  }
}

variable "github_repository_id" {
  description = "Immutable numeric GitHub repository ID (GET /repos/<owner>/<repo> -> .id). Required when enable_github_wif = true."
  type        = string
  default     = null

  validation {
    condition     = var.github_repository_id == null || can(regex("^[0-9]+$", var.github_repository_id))
    error_message = "github_repository_id must be numeric (digits only)."
  }
}

variable "github_repository_owner_id" {
  description = "Immutable numeric GitHub owner ID (GET /repos/<owner>/<repo> -> .owner.id). Required when enable_github_wif = true."
  type        = string
  default     = null

  validation {
    condition     = var.github_repository_owner_id == null || can(regex("^[0-9]+$", var.github_repository_owner_id))
    error_message = "github_repository_owner_id must be numeric (digits only)."
  }
}

variable "github_wif_pool_id" {
  description = "Workload Identity Pool ID for the GitHub pool. Change it if you re-enable GitHub WIF within 30 days of the old pool being deleted (pool IDs are soft-deleted and not reusable for 30 days)."
  type        = string
  default     = "github-pool"
}

# Terraform Cloud Configuration
variable "enable_tfc_oidc" {
  description = "Enable Terraform Cloud OIDC for Dynamic Credentials"
  type        = bool
  default     = true
}

variable "tfc_organization" {
  description = "Terraform Cloud organization name. Required (non-null) when enable_tfc_oidc = true — leaving it null while enable_tfc_oidc = true silently skips pool creation with no error."
  type        = string
  default     = null

  validation {
    condition     = var.tfc_organization == null || can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]*$", var.tfc_organization))
    error_message = "tfc_organization must contain only alphanumeric characters and hyphens."
  }

  validation {
    condition     = !var.enable_tfc_oidc || var.tfc_organization != null
    error_message = "tfc_organization must be set (non-null) when enable_tfc_oidc = true. The TFC OIDC pool is silently skipped when tfc_organization is null."
  }
}

variable "tfc_organization_id" {
  description = "Optional immutable TFC organization ID (org-xxxxxxxx). When set, the WIF provider condition also pins it, so a renamed/re-registered organization name cannot satisfy the trust."
  type        = string
  default     = null
}

variable "tfc_project_ids" {
  description = "Optional allow-list of TFC project IDs (prj-xxxxxxxx) the GCP workspaces live in. When non-empty, the WIF provider condition rejects tokens from workspaces in any other TFC project (blocks workspace-name squatting elsewhere in the org)."
  type        = list(string)
  default     = []
}

variable "control_plane_workspaces" {
  description = "TFC workspace name for each GCP control-plane stage. Keys are fixed: bootstrap, organization, projects, network-hub. Each workspace's plan phase is bound to <prefix>-<stage>-plan and its apply phase to <prefix>-<stage>-apply (bootstrap apply = the terraform-admin SA)."
  type        = map(string)
  default = {
    bootstrap     = "gcp-bootstrap"
    organization  = "gcp-organization"
    projects      = "gcp-projects"
    "network-hub" = "gcp-network-hub"
  }

  validation {
    condition     = toset(keys(var.control_plane_workspaces)) == toset(["bootstrap", "organization", "projects", "network-hub"])
    error_message = "control_plane_workspaces must have exactly the keys bootstrap, organization, projects, network-hub."
  }
}

variable "workload_environments" {
  description = "Application environment keys. Each gets a <prefix>-wl-<env>-plan / -apply SA pair, bound to TFC workspace <tfc_workload_workspace_prefix><env>. These SAs get NO org-level role; their folder roles are granted by the gcp-projects stage."
  type        = set(string)
  default     = []

  validation {
    condition     = alltrue([for e in var.workload_environments : can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", e)) && length("${var.project_prefix}-wl-${e}-apply") <= 30])
    error_message = "Each workload environment key must be lowercase alphanumeric/hyphen, and <project_prefix>-wl-<env>-apply must be <= 30 characters (GCP SA account_id limit). Shorten the env key or project_prefix."
  }
}

variable "tfc_workload_workspace_prefix" {
  description = "TFC workspace name prefix for per-environment workload workspaces (workspace = <prefix><env>)."
  type        = string
  default     = "gcp-workload-"
}

variable "tfc_workspace_ids" {
  description = "Optional map of TFC workspace NAME -> immutable workspace ID (ws-xxxxxxxx). When a workspace has an entry, its WIF bindings match the immutable ID (attribute.workspace_id_phase) instead of the name, so deleting/recreating or squatting the name gains nothing."
  type        = map(string)
  default     = {}
}

variable "workload_folder_roles" {
  description = "Roles the gcp-projects stage grants each workload plan/apply SA on its OWN environment folder. Also the allow-list (with network_folder_roles) for the projects-apply SA's delegated folder-IAM grant. Avoid roles/owner: anything listed here becomes grantable on ANY folder by projects-apply."
  type = object({
    plan  = list(string)
    apply = list(string)
  })
  default = {
    plan = [
      "roles/viewer",
      "roles/iam.securityReviewer",
      "roles/resourcemanager.folderViewer",
    ]
    apply = [
      "roles/resourcemanager.projectIamAdmin",
      "roles/iam.serviceAccountAdmin",
      "roles/iam.serviceAccountUser",
      "roles/serviceusage.serviceUsageAdmin",
      "roles/compute.admin",
      "roles/compute.xpnAdmin",
      "roles/servicenetworking.networksAdmin",
      "roles/dns.admin",
      "roles/secretmanager.admin",
      "roles/storage.admin",
      "roles/cloudkms.admin",
      "roles/bigquery.admin",
      "roles/logging.admin",
      "roles/monitoring.admin",
      "roles/pubsub.admin",
      "roles/run.admin",
      "roles/artifactregistry.admin",
      # Needed by resources the workload root actually manages:
      "roles/resourcemanager.projectCreator", # service_teams projects (stages/workload)
      "roles/iam.workloadIdentityPoolAdmin",  # app deploy WIF pool (stages/app-services)
      "roles/cloudsql.admin",                 # app-services databases
      "roles/container.admin",                # optional GKE Autopilot
      "roles/osconfig.patchDeploymentAdmin",  # VM Manager patch deployments (ops/os-config)
    ]
  }

  validation {
    condition     = !contains(concat(var.workload_folder_roles.plan, var.workload_folder_roles.apply), "roles/owner")
    error_message = "roles/owner must not be a workload folder role: it would become delegable by projects-apply on every folder."
  }
}

variable "network_folder_roles" {
  description = "Roles the gcp-projects stage grants the network-hub plan/apply SAs on the `shared` folder (hub + DNS projects, hierarchical firewall policy, Shared VPC host)."
  type = object({
    plan  = list(string)
    apply = list(string)
  })
  default = {
    plan = [
      "roles/compute.viewer",
      "roles/dns.reader",
      "roles/serviceusage.serviceUsageViewer",
    ]
    apply = [
      "roles/compute.networkAdmin",
      "roles/compute.securityAdmin",
      "roles/compute.xpnAdmin",
      "roles/compute.orgFirewallPolicyAdmin",
      "roles/compute.orgSecurityResourceAdmin",
      "roles/dns.admin",
      "roles/servicenetworking.networksAdmin",
      "roles/serviceusage.serviceUsageAdmin",
    ]
  }

  validation {
    condition     = !contains(concat(var.network_folder_roles.plan, var.network_folder_roles.apply), "roles/owner")
    error_message = "roles/owner must not be a network folder role: it would become delegable by projects-apply on every folder."
  }
}

variable "workload_billing_roles" {
  description = "Billing-account roles for each workload SA (budgets live on the billing account, not a folder). Not org-level."
  type = object({
    plan  = list(string)
    apply = list(string)
  })
  default = {
    plan  = ["roles/billing.viewer"]
    apply = ["roles/billing.costsManager", "roles/billing.user"] # billing.user: link service_teams projects
  }
}

variable "vpc_sc_access_policy_id" {
  description = "Optional numeric Access Context Manager policy ID. When set, workload apply SAs get roles/accesscontextmanager.policyEditor (plan: policyReader) on THIS policy only, so gcp-workload-<env> can manage its own perimeter without an org-level role."
  type        = string
  default     = null

  validation {
    condition     = var.vpc_sc_access_policy_id == null || can(regex("^[0-9]+$", var.vpc_sc_access_policy_id))
    error_message = "vpc_sc_access_policy_id must be the numeric access policy ID (without the accessPolicies/ prefix)."
  }
}
