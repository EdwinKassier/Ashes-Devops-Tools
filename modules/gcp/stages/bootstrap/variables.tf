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
  description = "Create the GitHub Actions WIF pool. Default false: no workflow in this repo uses GCP OIDC, so a standing trust is unused privilege. When true, the trust is pinned to github_repository_id + github_repository_owner_id on refs/heads/main and bound ONLY to the read-only organization plan SA."
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
  description = "Optional map of TFC workspace NAME -> immutable workspace ID (ws-xxxxxxxx). When a workspace has an entry, its WIF bindings match the immutable ID (attribute.workspace_id_phase) instead of the name, so deleting/recreating or squatting the name gains nothing. Expected for every control-plane workspace and every production workload workspace (see production_workload_environments)."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for id in values(var.tfc_workspace_ids) : can(regex("^ws-[A-Za-z0-9]+$", id)) && !can(regex("(?i)(replace|changeme|xxxx)", id))])
    error_message = "tfc_workspace_ids values must be real TFC workspace IDs (ws-<alphanumerics>, from the tfc-admin root output or the TFC UI). Placeholders such as ws-REPLACEME are rejected."
  }
}

variable "production_workload_environments" {
  description = "Subset of workload_environments that are production (the environments map entries with is_production = true). A check warns when any of their workspaces, or any control-plane workspace, is still WIF-bound by mutable NAME instead of an immutable tfc_workspace_ids entry."
  type        = set(string)
  default     = []

  validation {
    condition     = length(setsubtract(var.production_workload_environments, var.workload_environments)) == 0
    error_message = "production_workload_environments must be a subset of workload_environments."
  }
}

variable "workload_folder_roles" {
  description = "Roles the gcp-projects stage grants each workload plan/apply SA on its OWN environment folder. Also the allow-list (with network_folder_roles) for the projects-apply SA's delegated folder-IAM grant. Avoid roles/owner: anything listed here becomes grantable on ANY folder by projects-apply."
  type = object({
    plan  = list(string)
    apply = list(string)
  })
  default = {
    # Metadata-only viewers; the plan viewer custom role (enable_plan_viewer_role)
    # is appended. Deliberately NOT roles/viewer, which reads object/table data.
    plan = [
      "roles/resourcemanager.folderViewer",
      "roles/iam.securityReviewer",
      "roles/iam.serviceAccountViewer",
      "roles/iam.workloadIdentityPoolViewer",
      "roles/serviceusage.serviceUsageViewer",
      "roles/compute.viewer",
      "roles/dns.reader",
      "roles/cloudkms.viewer",
      "roles/secretmanager.viewer",
      "roles/pubsub.viewer",
      "roles/bigquery.metadataViewer",
      "roles/cloudsql.viewer",
      "roles/run.viewer",
      "roles/container.clusterViewer",
      "roles/monitoring.viewer",
      "roles/osconfig.patchDeploymentViewer",
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
    error_message = "roles/owner must not be a workload folder role: it would become delegable by projects-apply on the environment folders."
  }

  validation {
    condition     = length(setintersection(toset(var.workload_folder_roles.plan), toset(["roles/viewer", "roles/editor", "roles/owner"]))) == 0
    error_message = "workload_folder_roles.plan must not contain roles/viewer, roles/editor or roles/owner: roles/viewer reads Cloud Storage objects and BigQuery table data. Use metadata-only viewers plus the plan viewer custom role."
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
    error_message = "roles/owner must not be a network folder role: it would become delegable by projects-apply on the shared folder."
  }

  validation {
    condition     = length(setintersection(toset(var.network_folder_roles.plan), toset(["roles/viewer", "roles/editor", "roles/owner"]))) == 0
    error_message = "network_folder_roles.plan must not contain roles/viewer, roles/editor or roles/owner (data access from a plan identity)."
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
  description = "Optional numeric ID of the org-wide Access Context Manager policy. Only used with enable_legacy_org_access_policy_grants = true. The default model gives each environment its own folder-scoped access policy (created by gcp-organization), so a workload SA can never edit another environment's or the hub's perimeter."
  type        = string
  default     = null

  validation {
    condition     = var.vpc_sc_access_policy_id == null || can(regex("^[0-9]+$", var.vpc_sc_access_policy_id))
    error_message = "vpc_sc_access_policy_id must be the numeric access policy ID (without the accessPolicies/ prefix)."
  }
}

variable "enable_legacy_org_access_policy_grants" {
  description = "LEGACY. Grant every workload apply SA roles/accesscontextmanager.policyEditor (plan: policyReader) on the org-wide policy vpc_sc_access_policy_id. Any one environment could then edit every perimeter in the org, including production and the hub. Default false: use enable_scoped_access_policies instead. Enable only while migrating an existing deployment whose workload perimeters still live in the org-wide policy."
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_legacy_org_access_policy_grants || var.vpc_sc_access_policy_id != null
    error_message = "enable_legacy_org_access_policy_grants = true requires vpc_sc_access_policy_id."
  }
}

variable "enable_scoped_access_policies" {
  description = "Default model for workload VPC-SC: gcp-organization creates one folder-scoped access policy per environment folder and grants that environment's SAs rights on it only. This grants the organization stage SAs what that needs (apply: roles/accesscontextmanager.policyAdmin, plan: policyReader at the org node). Keep it in step with the gcp-organization enable_scoped_access_policies input. Default true."
  type        = bool
  default     = true
}

variable "enable_org_level_folder_iam_delegation" {
  description = "LEGACY. Bind the projects-apply conditional roles/resourcemanager.folderIamAdmin at the ORG node, where it applies to every folder. Default false: gcp-organization binds it on each environment folder (workload roles only) and the shared folder (network roles only). Enable only to bridge a migration until gcp-organization has been re-applied."
  type        = bool
  default     = false
}

variable "enable_plan_viewer_role" {
  description = "Create the org custom role plan_viewer_role_id (metadata-only get/list/getIamPolicy, no data access) and grant it to the plan identities: organization-plan on the admin project, and (through the gcp-projects folder grants) the workload and network plan SAs. Default true. Needs roles/iam.organizationRoleAdmin for the bootstrap apply identity (granted here)."
  type        = bool
  default     = true
}

variable "plan_viewer_role_id" {
  description = "role_id of the org-level plan viewer custom role. A deleted custom role ID is unusable for 37 days, so change it if you recreate the role within that window."
  type        = string
  default     = "landingZonePlanViewer"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.]{3,64}$", var.plan_viewer_role_id))
    error_message = "plan_viewer_role_id must be 3-64 characters of letters, digits, '_' and '.'."
  }
}

variable "plan_viewer_permissions" {
  description = "Permissions of the plan viewer custom role. Metadata-only by design: it fills the gaps left by the predefined metadata viewers in the plan role lists (bucket and repository metadata, logging and monitoring configuration). Data-plane permissions (object reads, table data, secret payloads, decrypt, log entries, token minting) are rejected."
  type        = list(string)
  default = [
    "artifactregistry.repositories.get",
    "artifactregistry.repositories.getIamPolicy",
    "artifactregistry.repositories.list",
    "iam.roles.get",
    "iam.roles.list",
    "logging.buckets.get",
    "logging.buckets.list",
    "logging.exclusions.get",
    "logging.exclusions.list",
    "logging.logMetrics.get",
    "logging.logMetrics.list",
    "logging.sinks.get",
    "logging.sinks.list",
    "logging.views.get",
    "logging.views.list",
    "monitoring.alertPolicies.get",
    "monitoring.alertPolicies.list",
    "monitoring.dashboards.get",
    "monitoring.dashboards.list",
    "monitoring.notificationChannels.get",
    "monitoring.notificationChannels.list",
    "resourcemanager.folders.get",
    "resourcemanager.projects.get",
    "resourcemanager.tagKeys.get",
    "resourcemanager.tagValues.get",
    "storage.buckets.get",
    "storage.buckets.getIamPolicy",
    "storage.buckets.list",
    "storage.buckets.listEffectiveTags",
    "storage.buckets.listTagBindings",
  ]

  validation {
    condition     = length(var.plan_viewer_permissions) > 0
    error_message = "plan_viewer_permissions must not be empty (set enable_plan_viewer_role = false instead)."
  }

  validation {
    condition = length(setintersection(toset(var.plan_viewer_permissions), toset([
      "storage.objects.get",
      "storage.objects.list",
      "bigquery.tables.getData",
      "bigquery.tables.export",
      "bigquery.jobs.create",
      "secretmanager.versions.access",
      "cloudkms.cryptoKeyVersions.useToDecrypt",
      "logging.logEntries.list",
      "logging.privateLogEntries.list",
      "logging.views.access",
      "artifactregistry.repositories.downloadArtifacts",
      "cloudsql.instances.export",
      "iam.serviceAccounts.getAccessToken",
      "iam.serviceAccounts.actAs",
    ]))) == 0
    error_message = "plan_viewer_permissions must not contain data-plane permissions (storage.objects.get/list, bigquery.tables.getData/export, bigquery.jobs.create, secretmanager.versions.access, cloudkms.cryptoKeyVersions.useToDecrypt, logging.logEntries.list, logging.privateLogEntries.list, logging.views.access, artifactregistry.repositories.downloadArtifacts, cloudsql.instances.export, iam.serviceAccounts.getAccessToken/actAs)."
  }

  validation {
    condition     = alltrue([for p in var.plan_viewer_permissions : can(regex("\\.(get|list|getIamPolicy|listEffectiveTags|listTagBindings)$", p))])
    error_message = "plan_viewer_permissions may only contain get / list / getIamPolicy / listEffectiveTags / listTagBindings permissions."
  }
}

variable "enable_pam" {
  description = "Grant the organization stage SAs Privileged Access Manager rights at the org node (apply: roles/privilegedaccessmanager.admin, plan: viewer) so gcp-organization can manage the just-in-time org-admin entitlement. Keep it in step with the gcp-organization enable_pam input. Default false."
  type        = bool
  default     = false
}

variable "enable_phase0_admin_impersonation" {
  description = "Let user:<admin_email> impersonate the terraform-admin (gcp-bootstrap apply) SA. Needed for the documented phase-0 first apply, which runs as a human admin. Set false on pass 2, once gcp-bootstrap applies through TFC dynamic credentials, so no standing human path to the bootstrap apply identity remains."
  type        = bool
  default     = true
}

variable "guardrail_owner_mode" {
  description = "Who owns IAM deny policies. \"separate\" (default): a dedicated <prefix>-guardrails-apply SA is the only automation identity with roles/iam.denyAdmin; the organization apply SA no longer holds it, so it cannot delete the containment deny policy that constrains it. \"organization\": legacy, the organization apply SA holds denyAdmin and gcp-organization manages the deny policies itself. Keep it in step with the gcp-organization guardrail_owner_mode input (it defaults to this stage's output)."
  type        = string
  default     = "separate"

  validation {
    condition     = contains(["separate", "organization"], var.guardrail_owner_mode)
    error_message = "guardrail_owner_mode must be \"separate\" or \"organization\"."
  }
}

variable "guardrail_owner_members" {
  description = "Principals allowed to impersonate the guardrails SA (roles/iam.serviceAccountTokenCreator) when guardrail_owner_mode = \"separate\". Use a group whose membership is granted just in time (PAM) and is disjoint from the people who can change the gcp-organization workspace. Empty = nobody can use the SA until set."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for m in var.guardrail_owner_members : can(regex("^(group|user|serviceAccount):[^@]+@[^@]+$", m))])
    error_message = "guardrail_owner_members entries must be group:<email>, user:<email> or serviceAccount:<email>."
  }
}

variable "enable_principal_access_boundary" {
  description = "Grant the organization stage SAs what the gcp-organization principal access boundary policy needs (apply: roles/iam.principalAccessBoundaryAdmin at the org and roles/resourcemanager.projectIamAdmin on the admin project for the policy binding; plan: roles/iam.principalAccessBoundaryViewer). Keep it in step with the gcp-organization enable_principal_access_boundary input. Default false."
  type        = bool
  default     = false
}
