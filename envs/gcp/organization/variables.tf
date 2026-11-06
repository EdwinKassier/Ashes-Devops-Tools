variable "landing_zone_config_path" {
  description = "Path to the single-source landing-zone config (YAML; schema config/landing-zone.example.yaml), absolute or relative to this root. Null = ../../../config/landing-zone.yaml; \"\" disables the lookup. Read only if the file exists; explicit variables win over its values."
  type        = string
  default     = null
}

variable "domain" {
  description = "The domain name of the organization (e.g., 'example.com'). Null = org.domain from config/landing-zone.yaml."
  type        = string
  default     = null

  validation {
    condition     = length(trimspace(coalesce(var.domain, local.cfg.domain, " "))) > 0
    error_message = "domain is unset: set var.domain or org.domain in config/landing-zone.yaml."
  }
}

variable "project_prefix" {
  description = <<-EOT
    Short prefix prepended to all GCP project IDs to ensure global uniqueness.
    Must start with a lowercase letter; only lowercase letters, digits, and hyphens allowed.
    Keep this to 6 characters or fewer — GCP project IDs are capped at 30 characters and
    the prefix consumes part of that budget. Null = org.prefix from
    config/landing-zone.yaml (shared by every GCP root). The placeholder "my-org" is rejected.
  EOT
  type        = string
  default     = null

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,9}$", coalesce(var.project_prefix, local.cfg.project_prefix, "!unset")))
    error_message = "project_prefix is unset or invalid: set var.project_prefix or org.prefix in config/landing-zone.yaml. It must start with a lowercase letter, contain only lowercase letters, digits, and hyphens, and be 10 characters or fewer."
  }

  validation {
    condition     = coalesce(var.project_prefix, local.cfg.project_prefix, "!unset") != "my-org"
    error_message = "project_prefix is still set to the placeholder 'my-org'. Set it to your organisation's actual identifier before deploying."
  }
}

variable "organization_name" {
  description = "Name of the organization. Null = org.display_name from config/landing-zone.yaml, else \"My Organization\"."
  type        = string
  default     = null
}

# customer_id is now fetched dynamically via data.google_organization

variable "billing_account" {
  description = "Billing account ID (optional if billing_account_display_name is provided). Null = gcp.billing_account from config/landing-zone.yaml."
  type        = string
  default     = null

  validation {
    condition     = coalesce(var.billing_account, local.cfg.billing_account, var.billing_account_display_name, "!unset") != "!unset"
    error_message = "At least one of billing_account (or gcp.billing_account in config/landing-zone.yaml) or billing_account_display_name must be set."
  }

  validation {
    condition     = !startswith(coalesce(var.billing_account, local.cfg.billing_account, "ok"), "REPLACE_WITH")
    error_message = "billing_account is still the config/landing-zone.example.yaml placeholder: set your billing account ID."
  }
}

variable "billing_account_display_name" {
  description = "Display name of the billing account (used if billing_account ID is not provided)"
  type        = string
  default     = null
}

variable "tfc_organization" {
  description = "Terraform Cloud organization used for dynamic credentials. Null = org.tfc.organization from config/landing-zone.yaml."
  type        = string
  default     = null
}

variable "shared_iam_group_role_bindings" {
  description = "Folder IAM bindings for the shared services folder, keyed by Google Group email"
  type        = map(set(string))
  default     = {}
}

variable "environments" {
  description = "Map of application environment definitions. is_production (default false) marks production environments: it drives the production guardrail checks here and in gcp-bootstrap / gcp-workload. Null = gcp.environments from config/landing-zone.yaml (the single source shared by every GCP root and tfc-admin)."
  type = map(object({
    display_name            = string
    region                  = string
    cidr_block              = string
    budget_monthly_limit    = number
    iam_group_role_bindings = map(set(string))
    labels                  = optional(map(string), {})
    is_production           = optional(bool, false)
  }))
  default = null

  validation {
    condition     = var.environments != null || length(local.cfg.environments) > 0
    error_message = "environments is unset: define gcp.environments in config/landing-zone.yaml or set var.environments."
  }

  # Environment keys become project/workspace keys (e.g. "<env>-host",
  # "gcp-workload-<env>"). "shared" is reserved for the hub/DNS projects: a
  # right-wins merge() would silently replace them with an environment named
  # "shared". Keys must also be a valid lowercase token.
  validation {
    condition     = alltrue([for k in(var.environments != null ? keys(var.environments) : keys(local.cfg.environments)) : k != "shared" && can(regex("^[a-z][a-z0-9-]{0,14}$", k))])
    error_message = "environments keys must be lowercase tokens (^[a-z][a-z0-9-]{0,14}$) and must not be the reserved key \"shared\"."
  }

  validation {
    condition     = alltrue([for c in(var.environments != null ? [for e in values(var.environments) : e.cidr_block] : [for e in values(local.cfg.environments) : e.cidr_block]) : can(cidrnetmask(c))])
    error_message = "Each environment's cidr_block must be valid CIDR notation, e.g. 10.10.0.0/16."
  }
}

variable "default_region" {
  description = "Default region for resources. Null = org.regions.gcp from config/landing-zone.yaml, else europe-west2."
  type        = string
  default     = null
}

variable "allowed_regions" {
  description = "List of allowed GCP regions for resource creation. Null = gcp.allowed_regions from config/landing-zone.yaml, else europe-west1/europe-west2/us-central1."
  type        = list(string)
  default     = null
}

variable "strict_folder_policy_environment_keys" {
  description = "Environment folder keys that should receive the stricter folder policy bundle"
  type        = list(string)
  default     = ["prod"]
}

variable "admin_email" {
  description = "Email address for the organization administrator. Null = gcp.admin_email from config/landing-zone.yaml."
  type        = string
  default     = null

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", coalesce(var.admin_email, local.cfg.admin_email, "!unset")))
    error_message = "admin_email is unset or not a valid email address: set var.admin_email or gcp.admin_email in config/landing-zone.yaml."
  }
}

variable "break_glass_user" {
  description = "Email address for the break glass user (optional). Always watched by the break-glass alert; granted Organization Admin only when allow_user_principals_for_break_glass = true."
  type        = string
  default     = null

  validation {
    condition     = var.break_glass_user == null || can(regex("^[^@]+@[^@]+\\.[^@]+$", var.break_glass_user))
    error_message = "break_glass_user must be a valid email address when provided."
  }
}

variable "organization_admin_groups" {
  description = "Bare group emails granted Organization Admin. Standing admin is group-only: at least one is required unless allow_user_principals_for_break_glass = true. Null = gcp.organization_admin_groups from config/landing-zone.yaml, else []."
  type        = list(string)
  default     = null
}

variable "billing_admin_groups" {
  description = "Bare group emails granted Billing Admin. At least one is required unless allow_user_principals_for_break_glass = true. Null = gcp.billing_admin_groups from config/landing-zone.yaml, else []."
  type        = list(string)
  default     = null
}

# Stage contract override (FAST-style): when set (here or as gcp.contracts.bootstrap
# in config/landing-zone.yaml) the gcp-bootstrap remote-state read is skipped.
variable "bootstrap_contract" {
  description = "gcp-bootstrap stage contract: admin_project_id, admin_project_number and terraform_admin_email, plus the optional automation identities (workload_service_accounts, stage_service_accounts, delegated_workload/network_folder_roles; omitted = no grants) and guardrail_owner_mode. Null = gcp.contracts.bootstrap from config/landing-zone.yaml, else read from the gcp-bootstrap workspace's remote state."
  type = object({
    admin_project_id                = string
    admin_project_number            = string
    terraform_admin_email           = string
    workload_service_accounts       = optional(map(object({ plan = string, apply = string })), {})
    stage_service_accounts          = optional(map(object({ plan = string, apply = string })), {})
    delegated_workload_folder_roles = optional(list(string), [])
    delegated_network_folder_roles  = optional(list(string), [])
    guardrail_owner_mode            = optional(string, "separate")
  })
  default = null

  validation {
    condition     = var.bootstrap_contract == null || can(regex("^[0-9]+$", var.bootstrap_contract.admin_project_number))
    error_message = "bootstrap_contract.admin_project_number must be numeric."
  }
}

variable "bootstrap_workspace_name" {
  description = "Name of the gcp-bootstrap TFC workspace this root reads via remote state for the admin project, Terraform admin SA, and WIF pools."
  type        = string
  default     = "gcp-bootstrap"
}

variable "security_contact_email" {
  description = "Email for security notifications via Essential Contacts (optional)"
  type        = string
  default     = null
}

variable "billing_contact_email" {
  description = "Email for billing notifications via Essential Contacts (optional)"
  type        = string
  default     = null
}

variable "monthly_budget_amount" {
  description = "Monthly budget limit for the organization. Set to 0 to disable budget alerts."
  type        = number
  default     = 1000
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

variable "custom_org_constraints" {
  description = "Opt-in custom organization-policy constraints (CEL-defined resource-shape guardrails), created AND enforced at the org node (enforcement = enforce | dry_run | off). Default [] = none. See docs/known-gaps.md."
  type = list(object({
    name           = string
    display_name   = string
    description    = string
    action_type    = string
    condition      = string
    method_types   = list(string)
    resource_types = list(string)
    enforcement    = optional(string, "enforce")
  }))
  default = []
}

variable "enable_audit_bucket_lock" {
  description = "Opt-in WORM lock on the org audit-log GCS bucket (locked retention of audit_log_retention_days). Default false preserves the current operator-correctable behaviour. A locked policy is IRREVERSIBLE — enable only for compliance regimes that require tamper-proof retention. See docs/known-gaps.md."
  type        = bool
  default     = false
}

variable "iam_deny_policies" {
  description = "Opt-in IAM deny policies applied at the org node — a coarse, allow-independent backstop blocking specific permissions for specific principals regardless of roles (deny before allow). Default [] = none. See docs/known-gaps.md."
  type = list(object({
    name         = string
    display_name = optional(string)
    rules = list(object({
      description           = optional(string)
      denied_principals     = list(string)
      denied_permissions    = list(string)
      exception_principals  = optional(list(string), [])
      exception_permissions = optional(list(string), [])
      denial_condition = optional(object({
        expression  = string
        title       = optional(string)
        description = optional(string)
      }))
    }))
  }))
  default = []
}

variable "terraform_admin_email" {
  description = <<-EOT
    Service account email for the Terraform admin SA created by the bootstrap stage.
    The organization providers impersonate this SA for all API calls, ensuring that
    even local runs operate with the SA's permissions rather than the caller's personal
    credentials.
    Format: terraform-admin@<admin-project-id>.iam.gserviceaccount.com
    Set to null only during the very first bootstrap apply when the SA does not exist yet.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.terraform_admin_email == null || can(regex("^[^@]+@[^@]+\\.iam\\.gserviceaccount\\.com$", var.terraform_admin_email))
    error_message = "terraform_admin_email must be a GCP service account email (ends in .iam.gserviceaccount.com) or null."
  }
}

# --- Dedicated logging project (opt-in, default = unchanged) ---
variable "logging_project_id" {
  description = "Dedicated logging project for the org audit sink/bucket, audit CMEK keyring and control-plane alerts (separation of duties). Default null = admin project. MUST NOT be owned by the Terraform admin/automation SA (create it out-of-band or from a separate identity). Decide before the first apply. Requires logging_project_number. PREVIEW: not yet validated against a real apply."
  type        = string
  default     = null
}

variable "logging_project_number" {
  description = "Project number of logging_project_id (required when it is set); used for the audit CMEK service-agent grants."
  type        = string
  default     = null
}

variable "audit_soft_delete_retention_days" {
  description = "Soft-delete window (days) on the org audit-log buckets (M-4). 7-90, or 0 to disable. Default 30."
  type        = number
  default     = 30
}

variable "enforce_os_login" {
  description = "Enforce compute.requireOsLogin at the organization node (CIS GCP 4.4). Default true."
  type        = bool
  default     = true
}

variable "os_login_exempt_environment_keys" {
  description = "Environment folder keys exempted from the org-wide OS Login requirement (folder-level override). Strict folders cannot be exempted. Default []."
  type        = list(string)
  default     = []
}

variable "enable_cis_log_metrics" {
  description = "CIS GCP 2.4-2.11 log-based metrics and alerts in the alerting project, fed org-wide by the aggregated org sink (requires enable_control_plane_alerting). Default true."
  type        = bool
  default     = true
}

variable "enable_control_plane_alerting" {
  description = "Log-match alerts on org IAM / org policy / VPC-SC / sink / custom-role / deny-policy / KMS-destroy changes and on break-glass use. Default true."
  type        = bool
  default     = true
}

variable "alert_notification_emails" {
  description = "Email addresses notified by the control-plane alerts. Empty (default) = gcp.alert_emails from config/landing-zone.yaml; a check warns when no destination is set."
  type        = list(string)
  default     = []
}

variable "alert_notification_channels" {
  description = "Existing Cloud Monitoring notification channel IDs (projects/<p>/notificationChannels/<id>) attached to every control-plane alert. Default []."
  type        = list(string)
  default     = []
}

variable "break_glass_principal_emails" {
  description = "Extra break-glass account emails whose admin actions raise a CRITICAL alert (break_glass_user is always included). List the members of a break-glass group here — group membership is not visible in audit logs."
  type        = list(string)
  default     = []
}

variable "enable_cmek_org_policy" {
  description = "Enforce CMEK on sensitive services org-wide (gcp.restrictNonCmekServices). Default false; set true (or use examples/presets/prod-gcp-organization.tfvars) once CMEK keys are wired for cmek_required_services."
  type        = bool
  default     = false
}

variable "cmek_required_services" {
  description = "Services that require CMEK when enable_cmek_org_policy is true."
  type        = list(string)
  default = [
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "sqladmin.googleapis.com",
    "spanner.googleapis.com",
    "pubsub.googleapis.com",
    "secretmanager.googleapis.com",
  ]
}

variable "enable_admin_containment" {
  description = "IAM deny policy blocking (for all but containment_exempt_principals) org-wide sink update/delete, exclusion changes, log-bucket delete and VPC-SC perimeter update/delete, plus — tag-scoped to the audit store — bucket delete/IAM change/untag, object delete, key-version destroy/disable and key IAM change. Once on, any sink/exclusion/perimeter change must be applied by break-glass. Null (default) = gcp.admin_containment from config, else ON whenever an environment is_production. Needs a break-glass principal (gcp.break_glass_group or containment_exempt_principals)."
  type        = bool
  default     = null
}

variable "containment_exempt_principals" {
  description = "Break-glass principals exempt from the admin-containment deny policy, as IAM v2 principal identifiers (e.g. principalSet://goog/group/break-glass@acme.com). Empty (default) = principalSet://goog/group/<gcp.break_glass_group> from config. Required (non-empty) when containment is on. Placeholder values (REPLACE-ME, your-domain, example.com, .invalid) are rejected so a copied preset fails loudly."
  type        = list(string)
  default     = []

  validation {
    condition     = !anytrue([for p in var.containment_exempt_principals : can(regex("(?i)(replace-me|your-domain|example\\.(com|org|net)|\\.invalid$|changeme)", p))])
    error_message = "containment_exempt_principals still contains a placeholder (REPLACE-ME / your-domain / example.com / .invalid). Set your real break-glass group before enabling admin containment."
  }
}

variable "enable_legacy_admin_folder_roles" {
  description = "Grant the phase-0 bootstrap SA (terraform_admin_email) folderAdmin/projectCreator/billing.projectManager/networkAdmin on every folder. Legacy single-identity model; default false because the per-stage plan/apply service accounts replace it. Enable only while migrating an existing deployment."
  type        = bool
  default     = false
}

variable "allow_user_principals_for_break_glass" {
  description = "Escape hatch: also grant admin_email and break_glass_user standing Organization Admin (admin_email also Billing Admin) as user: principals. Default false (groups only); prefer a break-glass group or enable_pam."
  type        = bool
  default     = false
}

variable "enable_pam" {
  description = "Create a just-in-time Privileged Access Manager entitlement for Organization Admin (pam_eligible_groups request, pam_approver_groups approve). Requires gcp-bootstrap enable_pam = true. Default false."
  type        = bool
  default     = false
}

variable "pam_eligible_groups" {
  description = "Bare group emails whose members may request just-in-time Organization Admin (enable_pam)."
  type        = list(string)
  default     = []
}

variable "pam_approver_groups" {
  description = "Bare group emails whose members approve just-in-time Organization Admin requests (enable_pam). Must not overlap pam_eligible_groups."
  type        = list(string)
  default     = []
}

variable "pam_max_request_duration" {
  description = "Maximum just-in-time grant duration, '<seconds>s' (max 86400s). Default 3600s."
  type        = string
  default     = "3600s"
}

variable "enable_scoped_access_policies" {
  description = "Create one folder-scoped VPC-SC access policy per environment and grant that environment's workload SAs rights on it only (gcp-workload builds its perimeter there). Requires gcp-bootstrap enable_scoped_access_policies = true. Default true."
  type        = bool
  default     = true
}

variable "guardrail_owner_mode" {
  description = "Who applies the org IAM deny policies: \"separate\" (the gcp-bootstrap guardrails SA, from the guardrail_deny_policy_specs output) or \"organization\" (this root; legacy). Null = the gcp-bootstrap guardrail_owner_mode output (\"organization\" for an older bootstrap state without it). Must match gcp-bootstrap: in separate mode this root's apply SA has no roles/iam.denyAdmin."
  type        = string
  default     = null

  validation {
    condition     = var.guardrail_owner_mode == null || contains(["separate", "organization"], coalesce(var.guardrail_owner_mode, "separate"))
    error_message = "guardrail_owner_mode must be \"separate\", \"organization\" or null."
  }
}

variable "prefer_managed_constraints" {
  description = "Use the managed (constraints/*.managed.*) successor of each baseline org-policy constraint where Google offers one. Default true."
  type        = bool
  default     = true
}

variable "enable_log_analytics" {
  description = "Org audit logs into a Log Analytics-enabled log bucket with a linked BigQuery dataset. Default true."
  type        = bool
  default     = true
}

variable "log_analytics_retention_days" {
  description = "Retention (days, 365-3650) of the audit Log Analytics bucket."
  type        = number
  default     = 400
}

variable "enable_logging_organization_settings" {
  description = "Manage org Cloud Logging settings (default log-bucket location = default_region, optional CMEK). Default false."
  type        = bool
  default     = false
}

variable "logging_settings_kms_key_name" {
  description = "Optional CMEK for new projects' _Default/_Required log buckets (grant the org Logging SA on it first). Null = Google-managed."
  type        = string
  default     = null
}

variable "enable_principal_access_boundary" {
  description = "Principal access boundary on every SA in the admin project (this org's resources only). Needs gcp-bootstrap enable_principal_access_boundary. Default false."
  type        = bool
  default     = false
}

variable "principal_access_boundary_allowed_resources" {
  description = "Extra/explicit resources the bounded automation SAs may act on. Empty = this organization only."
  type        = list(string)
  default     = []
}

variable "restrict_cloud_run_ingress" {
  description = "Enforce run.allowedIngress org-wide so Cloud Run services accept only internal or Cloud Load Balancing traffic (never ingress \"all\"). Public apps are served through the external ALB + Cloud Armor. Default true."
  type        = bool
  default     = true
}

variable "org_policy_overrides" {
  description = "Per-constraint overrides of the organization-policy baseline (stage org_policy_overrides): set enforce, replace list values, disabled = true to drop, or add a constraint. Use it instead of forking the stage."
  type = map(object({
    enforce        = optional(bool)
    allowed_values = optional(list(string))
    denied_values  = optional(list(string))
    allow_all      = optional(bool)
    deny_all       = optional(bool)
    disabled       = optional(bool, false)
  }))
  default  = {}
  nullable = false
}

variable "allowed_workload_identity_issuers" {
  description = "OIDC issuers workload identity pool providers may trust (org policy iam.workloadIdentityPoolProviders). Null = https://<tfc_hostname> plus GitHub Actions. Add GitLab / TFE hosts when used."
  type        = list(string)
  default     = null
}

variable "allowed_workload_identity_aws_accounts" {
  description = "AWS account IDs workload identity pools may federate (iam.workloadIdentityPoolAwsAccounts). Empty (default) denies AWS-account federation."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "tfc_hostname" {
  description = "HCP Terraform / Terraform Enterprise hostname whose dynamic-credential tokens the WIF pools trust (app.terraform.io, app.eu.terraform.io or your TFE host)."
  type        = string
  default     = "app.terraform.io"
}

variable "pin_wif_to_tfc_organization" {
  description = "Enforce (custom org-policy constraint) that every HCP Terraform workload identity provider references tfc_organization in its attribute_condition, so no pipeline can trust another TFC organization. Default true."
  type        = bool
  default     = true
}

variable "wif_github_owner_ids" {
  description = "Numeric GitHub owner IDs a GitHub Actions workload identity provider must condition on (repository_owner_id). Empty (default) leaves GitHub providers tenant-unpinned (the issuer is still allow-listed)."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "wif_tenant_pin_enforcement" {
  description = "custom.wifProviderTenantPinned: enforce (default), dry_run (log only: stage it first on an org with existing WIF providers) or off."
  type        = string
  default     = "enforce"
}
