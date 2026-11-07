variable "domain" {
  description = "The primary domain of the GCP organization (e.g., 'example.com')"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9.-]*\\.[a-zA-Z]{2,}$", var.domain))
    error_message = "domain must be a valid domain name (e.g., 'example.com')."
  }
}

variable "org_id" {
  description = "The numeric GCP organization ID (digits only, no 'organizations/' prefix)"
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.org_id))
    error_message = "org_id must contain only digits (e.g., '123456789012'). Do not include the 'organizations/' prefix."
  }
}

variable "admin_project_id" {
  description = "The project ID of the bootstrap admin project"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.admin_project_id))
    error_message = "admin_project_id must be 6-30 characters, start with a lowercase letter, and contain only lowercase letters, digits, and hyphens."
  }
}

variable "admin_project_number" {
  description = "The numeric project number of the bootstrap admin project (digits only)"
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.admin_project_number))
    error_message = "admin_project_number must contain only digits."
  }
}

variable "customer_id" {
  description = "The Google Workspace customer ID (format: 'C' followed by alphanumerics, e.g., 'C0abc1234')"
  type        = string

  validation {
    condition     = can(regex("^C[0-9a-z]+$", var.customer_id))
    error_message = "customer_id must start with 'C' followed by alphanumeric characters (e.g., 'C0abc1234')."
  }
}

variable "gcp" {
  description = "The gcp section of the organization stage: every tuning input the gcp-organization root takes from config/landing-zone.yaml (gcp.*) or from its gcp_overrides variable, in one object. Each attribute is documented in the type; an unset (or null) attribute takes the default shown there. admin_email is required. The root fills enable_admin_containment, containment_exempt_principals, guardrail_owner_mode and allowed_workload_identity_issuers from its own derivations."
  type = object({
    # Email address of the primary administrator. Granted standing org/billing admin as a user:
    # principal ONLY when allow_user_principals_for_break_glass = true.
    admin_email = optional(string)
    # Optional break-glass emergency user email. Always watched by the CRITICAL break-glass control-
    # plane alert; granted standing org admin ONLY when allow_user_principals_for_break_glass = true
    # (prefer a break-glass group, or the PAM entitlement).
    break_glass_user = optional(string)
    # Google Group email addresses (bare, no 'group:' prefix) granted
    # roles/resourcemanager.organizationAdmin. Standing org admin is group-only: must be non-empty
    # unless allow_user_principals_for_break_glass = true, and must not contain admin_email or
    # break_glass_user (those are users).
    organization_admin_groups = optional(list(string), [])
    # Google Group email addresses (bare, no 'group:' prefix) granted roles/billing.admin. Group-only
    # unless allow_user_principals_for_break_glass = true.
    billing_admin_groups = optional(list(string), [])
    # Escape hatch. When true, admin_email and break_glass_user are ALSO granted standing
    # roles/resourcemanager.organizationAdmin (and admin_email roles/billing.admin) as user:
    # principals. Default false: standing admin goes to groups only; use a break-glass group or the
    # PAM entitlement (enable_pam) for individual elevation.
    allow_user_principals_for_break_glass = optional(bool, false)
    # List of GCP regions permitted by resource location org policy
    allowed_regions = optional(list(string), ["europe-west1", "europe-west2", "us-central1"])
    # Subset of environment keys that enforce strict resource location policies
    strict_folder_policy_environment_keys = optional(list(string), ["prod"])
    # Enforce compute.requireOsLogin at the organization node (CIS GCP 4.4), so every VM in every
    # folder must use OS Login. Exempt folders via os_login_exempt_environment_keys. Default true.
    enforce_os_login = optional(bool, true)
    # Environment folder keys exempted from the org-wide OS Login requirement (a folder-level
    # compute.requireOsLogin = false override). Keys in strict_folder_policy_environment_keys cannot
    # be exempted. Default [] = no exemptions.
    os_login_exempt_environment_keys = optional(list(string), [])
    # Email address for security notifications via Essential Contacts (SCC alerts, compliance
    # notifications). Optional — if null, no Essential Contact is registered for the SECURITY
    # category.
    security_contact_email = optional(string)
    # Email address for billing notifications and budget alerts via Essential Contacts. Optional — if
    # null, no Essential Contact is registered for the BILLING category.
    billing_contact_email = optional(string)
    # ISO 4217 currency code for the budget (e.g., USD, EUR, GBP)
    budget_currency = optional(string, "USD")
    # Dedicated logging project ID for the org audit sink, audit bucket, BigQuery audit dataset, audit
    # CMEK keyring and control-plane alerts (separation of duties). Default null = the admin/bootstrap
    # project (unchanged). The project MUST NOT be owned (roles/owner, roles/editor, or storage/KMS
    # admin) by the Terraform admin / automation service account — otherwise the identity being
    # audited can delete object generations or destroy the key protecting its own audit trail. Create
    # it out-of-band (or from a separate identity) and grant the automation SA only what it needs to
    # manage the resources here. Decide BEFORE the first apply: KMS keys cannot be deleted, so moving
    # the audit keys later orphans the old ones. Requires logging_project_number. PREVIEW: not yet
    # validated against a real apply.
    logging_project_id = optional(string)
    # Numeric project number of logging_project_id (required when it is set). Used to grant the
    # logging project's GCS and BigQuery service agents access to the audit CMEK keys.
    logging_project_number = optional(string)
    # Soft-delete window (days) on the org audit-log buckets: deleted/overwritten objects stay
    # restorable for this long. 7-90, or 0 to disable. Default 30.
    audit_soft_delete_retention_days = optional(number, 30)
    # Create log-match alerts on control-plane changes (org IAM, org policy, VPC-SC, sinks/exclusions,
    # custom roles, deny policies, KMS key-version destroy/disable, tag binding/key/value deletion)
    # and on break-glass use, in the audit/logging project. Default true.
    enable_control_plane_alerting = optional(bool, true)
    # With enable_control_plane_alerting, also create the CIS GCP 2.4-2.11 log-based metrics and alert
    # policies (project ownership, audit config, custom roles, firewall rules, routes, networks, Cloud
    # Storage IAM, Cloud SQL config) in the audit/logging project. The aggregated org sink feeds them
    # every project's Admin Activity logs, so one set covers the org. Default true.
    enable_cis_log_metrics = optional(bool, true)
    # Email addresses notified by the control-plane alerts (one email channel each). Default [] — a
    # check warns if no destination is set.
    alert_notification_emails = optional(list(string), [])
    # IDs of existing Cloud Monitoring notification channels (projects/<p>/notificationChannels/<id>)
    # attached to every control-plane alert. Default [].
    alert_notification_channels = optional(list(string), [])
    # Extra break-glass principal emails (users/SAs) whose ANY admin action raises a CRITICAL control-
    # plane alert. break_glass_user is always included. Group membership is not visible in audit logs,
    # so list the member accounts of a break-glass group here.
    break_glass_principal_emails = optional(list(string), [])
    # Opt-in custom organization-policy constraints (CEL-defined resource-shape guardrails), created
    # AND enforced at the org node (enforcement = enforce | dry_run | off; dry_run logs violations
    # without blocking, the way to stage a new one). Default [] = none. See docs/known-gaps.md.
    custom_org_constraints = optional(list(object({
      name           = string
      display_name   = string
      description    = string
      action_type    = string
      condition      = string
      method_types   = list(string)
      resource_types = list(string)
      enforcement    = optional(string, "enforce")
    })), [])
    # Opt-in WORM lock on the org audit-log GCS bucket (a locked retention policy of
    # audit_log_retention_days). Default false preserves the current behaviour (versioned + access-
    # controlled but not immutable, and a lifecycle delete that can be corrected). Enable only for
    # compliance regimes that require tamper-proof retention — a locked policy CANNOT be shortened or
    # removed. See docs/known-gaps.md.
    enable_audit_bucket_lock = optional(bool, false)
    # Opt-in IAM deny policies applied at the org node — a coarse, allow-independent backstop that
    # blocks specific permissions for specific principals regardless of roles held (deny is evaluated
    # before allow). Default [] = none. See docs/known-gaps.md.
    iam_deny_policies = optional(list(object({
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
    })), [])
    # Enforce CMEK on sensitive services org-wide via the gcp.restrictNonCmekServices org policy.
    # Default false, so a default apply is unchanged; the prod-hardening preset turns it on. Enabling
    # denies creating resources in cmek_required_services without a customer-managed key, so wire CMEK
    # keys for those services first.
    enable_cmek_org_policy = optional(bool, false)
    # Services that require CMEK when enable_cmek_org_policy is true. Admins tune this list.
    cmek_required_services = optional(list(string), [
      "storage.googleapis.com",
      "bigquery.googleapis.com",
      "sqladmin.googleapis.com",
      "spanner.googleapis.com",
      "pubsub.googleapis.com",
      "secretmanager.googleapis.com",
    ])
    # IAM deny policy at the org node that blocks, for all principals except
    # containment_exempt_principals (break-glass): org-wide update/delete of logging sinks, exclusion
    # changes, log-bucket delete, VPC-SC perimeter update/delete/replaceAll/commit and access-policy
    # delete; and, scoped by the containment/protected tag to the audit buckets + audit CMEK keyring,
    # bucket delete/setIamPolicy/deleteTagBinding, object delete, key-version destroy/update (disable)
    # and key setIamPolicy. Once on, Terraform changes to ANY sink, exclusion or perimeter must run as
    # break-glass. Default false at this stage; the gcp-organization root derives it ON whenever an
    # environment is_production (and fails the plan without a break-glass principal). In
    # guardrail_owner_mode = "separate" this stage only creates and binds the containment/protected
    # tag; the gcp-guardrails root applies the policy itself.
    enable_admin_containment = optional(bool, false)
    # Break-glass principals exempt from the admin-containment deny policy, e.g.
    # ["principalSet://goog/group/break-glass@example.com"]. Required (non-empty) when
    # enable_admin_containment is true.
    containment_exempt_principals = optional(list(string), [])
    # Grant the phase-0 bootstrap SA (terraform_admin_email)
    # folderAdmin/projectCreator/billing.projectManager/networkAdmin on every folder. Legacy single-
    # identity model; default false because the per-stage plan/apply service accounts replace it.
    # Enable only while migrating an existing deployment.
    enable_legacy_admin_folder_roles = optional(bool, false)
    # Create one folder-scoped Access Context Manager policy per environment folder (every key in
    # environments except shared_folder_key) and grant that environment's workload SAs
    # (workload_service_accounts) policyEditor (apply) / policyReader (plan) on it only. The workload
    # root builds its perimeter in this policy. Requires the gcp-bootstrap
    # enable_scoped_access_policies input (policyAdmin for the organization apply SA). Default true.
    enable_scoped_access_policies = optional(bool, true)
    # Create a Privileged Access Manager entitlement at the org node: members of pam_eligible_groups
    # may request pam_roles for up to pam_max_request_duration, with justification, approved by
    # pam_approver_groups. Requires the gcp-bootstrap enable_pam input. Default false.
    enable_pam = optional(bool, false)
    # Bare group emails whose members may request the PAM entitlement. Required when enable_pam =
    # true.
    pam_eligible_groups = optional(list(string), [])
    # Bare group emails whose members approve PAM requests. Required when enable_pam = true; keep it
    # disjoint from pam_eligible_groups so nobody approves their own request.
    pam_approver_groups = optional(list(string), [])
    # Maximum duration of a PAM grant, in seconds with an 's' suffix (e.g. 3600s). Default 1 hour.
    pam_max_request_duration = optional(string, "3600s")
    # Who applies the org IAM deny policies (admin containment + iam_deny_policies). "separate"
    # (default): this stage neither builds nor applies them (its apply identity has no
    # roles/iam.denyAdmin, so it cannot delete the containment policy that constrains it); the gcp-
    # guardrails root authors them from config and applies them as the gcp-bootstrap
    # <prefix>-guardrails-apply SA. This stage still creates and binds the containment tag.
    # "organization": legacy, this stage applies them (needs gcp-bootstrap guardrail_owner_mode =
    # "organization"). Migrating from organization to separate: terraform state rm the module.iam_deny
    # resources here and import them into gcp-guardrails (UPGRADING.md).
    guardrail_owner_mode = optional(string, "separate")
    # Set every baseline org-policy constraint that has a like-for-like managed successor
    # (constraints/*.managed.*: service-account key creation/upload, default-SA basic roles, serial
    # port, OS Login, nested virtualization, guest attributes, VM external IPs, Cloud SQL public IP)
    # through the managed version. Default true. Constraints without a managed equivalent (and
    # iam.allowedPolicyMemberDomains, see docs/known-gaps.md) stay legacy.
    prefer_managed_constraints = optional(bool, true)
    # Route every org audit log into a Log Analytics-enabled Cloud Logging bucket in the audit
    # project, with a linked read-only BigQuery dataset. Default true.
    enable_log_analytics = optional(bool, true)
    # Retention (days) of the audit Log Analytics bucket. Locked (irreversibly) together with the GCS
    # audit bucket when enable_audit_bucket_lock = true.
    log_analytics_retention_days = optional(number, 400)
    # Manage the organization's Cloud Logging settings (google_logging_organization_settings): the
    # storage location of the _Default/_Required buckets of new projects
    # (logging_settings_storage_location, default default_region) and optionally their CMEK
    # (logging_settings_kms_key_name). Default false.
    enable_logging_organization_settings = optional(bool, false)
    # SCC API generation for the notification stream: v1 (default, unchanged), both (add the v2 twin
    # next to v1 to verify), or v2 (flip; v1 configs destroyed). See docs/runbooks/scc-v2-migration.md.
    scc_api_version = optional(string, "v1")
    # With enable_logging_organization_settings: disable the organization's _Default log sink, so new
    # projects stop routing org-level logs into the _Default bucket. Default false (unchanged). Only
    # the audit-log sinks (cloudaudit) are routed centrally, so enable it only after confirming the
    # non-audit org logs you need are covered by another sink.
    disable_default_sink = optional(bool, false)
    # Optional CMEK for the _Default/_Required buckets of new projects. Grant the org Cloud Logging
    # service account (gcloud logging settings describe --organization=<id>)
    # roles/cloudkms.cryptoKeyEncrypterDecrypter on the key first. Null = Google-managed encryption.
    logging_settings_kms_key_name = optional(string)
    # Bind a principal access boundary policy to every service account in the admin (automation)
    # project, so their permissions only work on resources in this organization (plus
    # principal_access_boundary_allowed_resources). Needs the gcp-bootstrap
    # enable_principal_access_boundary input. With enable_admin_containment the boundary's
    # update/delete/unbind is also denied to all but break-glass. Default false: validate on a non-
    # production org first.
    enable_principal_access_boundary = optional(bool, false)
    # Resources the bounded automation SAs may act on
    # (//cloudresourcemanager.googleapis.com/organizations|folders|projects/<id>). Empty = this
    # organization only.
    principal_access_boundary_allowed_resources = optional(list(string), [])
    # Enforce run.allowedIngress org-wide so Cloud Run services accept only internal or Cloud Load
    # Balancing traffic (never ingress "all"). Public apps are served through the external ALB + Cloud
    # Armor. Default true.
    restrict_cloud_run_ingress = optional(bool, true)
    # OIDC issuer URIs a workload identity pool provider may be created for (org policy
    # iam.workloadIdentityPoolProviders). Default: HCP Terraform dynamic credentials and GitHub
    # Actions (app-services deploy identities). Add https://gitlab.com (or your TFE / GitLab host)
    # when used. Empty denies every new provider.
    allowed_workload_identity_issuers = optional(list(string), ["https://app.terraform.io", "https://token.actions.githubusercontent.com"])
    # AWS account IDs a workload identity pool may federate (org policy
    # iam.workloadIdentityPoolAwsAccounts). Empty (default) denies AWS-account federation.
    allowed_workload_identity_aws_accounts = optional(list(string), [])
    # Per-constraint overrides of the organization-policy baseline, keyed by constraint name (e.g.
    # compute.requireOsLogin). For a boolean constraint set enforce. For a list constraint set
    # allowed_values / denied_values / allow_all / deny_all, which replace the baseline values.
    # disabled = true drops the constraint from the baseline. A constraint not in the baseline is
    # added. Use this instead of forking the stage when a single guardrail does not fit.
    org_policy_overrides = optional(map(object({
      enforce        = optional(bool)
      allowed_values = optional(list(string))
      denied_values  = optional(list(string))
      allow_all      = optional(bool)
      deny_all       = optional(bool)
      disabled       = optional(bool, false)
    })), {})
    # How custom.wifProviderTenantPinned is applied: enforce (default; providers that do not pin the
    # tenant are rejected), dry_run (violations are only logged: stage it this way on an org with
    # existing providers), or off.
    wif_tenant_pin_enforcement = optional(string, "enforce")
  })
  default  = {}
  nullable = false

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.gcp.admin_email))
    error_message = "admin_email is unset or not a valid email address: set gcp.admin_email in config/landing-zone.yaml (or gcp_overrides.admin_email in the gcp-organization root)."
  }

  validation {
    condition     = var.gcp.break_glass_user == null || can(regex("^[^@]+@[^@]+\\.[^@]+$", var.gcp.break_glass_user))
    error_message = "gcp_overrides.break_glass_user must be null or a valid email address."
  }

  validation {
    condition     = alltrue([for g in var.gcp.organization_admin_groups : can(regex("^[^@:\\s]+@[^@\\s]+\\.[^@\\s]+$", g))])
    error_message = "Each gcp_overrides.organization_admin_groups entry must be a bare group email address (no 'user:'/'group:'/'serviceAccount:' prefix)."
  }

  validation {
    condition     = length(var.gcp.organization_admin_groups) > 0 || var.gcp.allow_user_principals_for_break_glass
    error_message = "gcp_overrides.organization_admin_groups must list at least one group (gcp.organization_admin_groups in config/landing-zone.yaml): standing org admin is granted to groups only. To grant gcp_overrides.admin_email / gcp_overrides.break_glass_user as users instead, set gcp_overrides.allow_user_principals_for_break_glass = true (break-glass only)."
  }

  validation {
    condition     = !contains([for g in var.gcp.organization_admin_groups : lower(g)], lower(coalesce(var.gcp.admin_email, "-"))) && (var.gcp.break_glass_user == null || !contains([for g in var.gcp.organization_admin_groups : lower(g)], lower(coalesce(var.gcp.break_glass_user, "-"))))
    error_message = "gcp_overrides.organization_admin_groups must not contain gcp_overrides.admin_email or gcp_overrides.break_glass_user: they are user accounts and would be bound as group: principals."
  }

  validation {
    condition     = alltrue([for g in var.gcp.billing_admin_groups : can(regex("^[^@:\\s]+@[^@\\s]+\\.[^@\\s]+$", g))])
    error_message = "Each gcp_overrides.billing_admin_groups entry must be a bare group email address (no 'user:'/'group:'/'serviceAccount:' prefix)."
  }

  validation {
    condition     = length(var.gcp.billing_admin_groups) > 0 || var.gcp.allow_user_principals_for_break_glass
    error_message = "gcp_overrides.billing_admin_groups must list at least one group (gcp.billing_admin_groups in config/landing-zone.yaml): standing billing admin is granted to groups only (or set gcp_overrides.allow_user_principals_for_break_glass = true)."
  }

  validation {
    condition     = length(var.gcp.allowed_regions) > 0
    error_message = "gcp_overrides.allowed_regions (gcp.allowed_regions in config/landing-zone.yaml) must contain at least one region."
  }

  validation {
    condition     = length(setintersection(toset(var.gcp.os_login_exempt_environment_keys), toset(var.gcp.strict_folder_policy_environment_keys))) == 0
    error_message = "gcp_overrides.os_login_exempt_environment_keys must not include a strict folder (gcp_overrides.strict_folder_policy_environment_keys always requires OS Login)."
  }

  validation {
    condition     = var.gcp.security_contact_email == null || can(regex("^[^@]+@[^@]+\\.[^@]+$", var.gcp.security_contact_email))
    error_message = "gcp_overrides.security_contact_email must be a valid email address when provided."
  }

  validation {
    condition     = var.gcp.billing_contact_email == null || can(regex("^[^@]+@[^@]+\\.[^@]+$", var.gcp.billing_contact_email))
    error_message = "gcp_overrides.billing_contact_email must be a valid email address when provided."
  }

  validation {
    condition     = can(regex("^[A-Z]{3}$", var.gcp.budget_currency))
    error_message = "gcp_overrides.budget_currency must be a 3-letter ISO 4217 currency code (e.g., USD, EUR)."
  }

  validation {
    condition     = var.gcp.logging_project_id == null || can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.gcp.logging_project_id))
    error_message = "gcp_overrides.logging_project_id must be null or a valid GCP project ID."
  }

  validation {
    condition     = var.gcp.logging_project_number == null || can(regex("^[0-9]+$", var.gcp.logging_project_number))
    error_message = "gcp_overrides.logging_project_number must contain only digits."
  }

  validation {
    condition     = var.gcp.logging_project_id == null || var.gcp.logging_project_number != null
    error_message = "gcp_overrides.logging_project_number is required when gcp_overrides.logging_project_id is set."
  }

  validation {
    condition     = var.gcp.audit_soft_delete_retention_days == 0 || (var.gcp.audit_soft_delete_retention_days >= 7 && var.gcp.audit_soft_delete_retention_days <= 90)
    error_message = "gcp_overrides.audit_soft_delete_retention_days must be 0 or between 7 and 90."
  }

  validation {
    condition     = alltrue([for e in var.gcp.alert_notification_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "Each gcp_overrides.alert_notification_emails entry must be a valid email address."
  }

  validation {
    condition     = alltrue([for c in var.gcp.alert_notification_channels : can(regex("^projects/[^/]+/notificationChannels/[^/]+$", c))])
    error_message = "Each gcp_overrides.alert_notification_channels entry must be projects/<project>/notificationChannels/<id>."
  }

  validation {
    condition     = !var.gcp.enable_admin_containment || length(var.gcp.containment_exempt_principals) > 0
    error_message = "gcp_overrides.containment_exempt_principals must be non-empty when gcp_overrides.enable_admin_containment is true, or the deny applies to everyone including break-glass."
  }

  validation {
    condition     = alltrue([for p in var.gcp.containment_exempt_principals : can(regex("^principal(Set)?://", p))])
    error_message = "gcp_overrides.containment_exempt_principals entries must be IAM v2 principal identifiers (principal://... or principalSet://...), e.g. principalSet://goog/group/break-glass@acme.com."
  }

  validation {
    condition     = !anytrue([for p in var.gcp.containment_exempt_principals : can(regex("(?i)(replace-me|your-domain|example\\.(com|org|net)|\\.invalid$|changeme)", p))])
    error_message = "gcp_overrides.containment_exempt_principals (gcp.break_glass_group in config/landing-zone.yaml) still contains a placeholder (REPLACE-ME / your-domain / example.com / .invalid). Set your real break-glass group before enabling admin containment."
  }

  validation {
    condition     = !var.gcp.enable_pam || length(var.gcp.pam_eligible_groups) > 0
    error_message = "gcp_overrides.pam_eligible_groups must be non-empty when gcp_overrides.enable_pam = true."
  }

  validation {
    condition     = alltrue([for g in var.gcp.pam_eligible_groups : can(regex("^[^@:\\s]+@[^@\\s]+\\.[^@\\s]+$", g)) && !can(regex("(?i)(replace-me|\\.invalid$)", g))])
    error_message = "gcp_overrides.pam_eligible_groups entries must be bare group email addresses (placeholders such as REPLACE-ME / .invalid are rejected)."
  }

  validation {
    condition     = !var.gcp.enable_pam || length(var.gcp.pam_approver_groups) > 0
    error_message = "gcp_overrides.pam_approver_groups must be non-empty when gcp_overrides.enable_pam = true."
  }

  validation {
    condition     = length(setintersection(toset(var.gcp.pam_approver_groups), toset(var.gcp.pam_eligible_groups))) == 0
    error_message = "gcp_overrides.pam_approver_groups must not overlap gcp_overrides.pam_eligible_groups (self-approval)."
  }

  validation {
    condition     = alltrue([for g in var.gcp.pam_approver_groups : can(regex("^[^@:\\s]+@[^@\\s]+\\.[^@\\s]+$", g)) && !can(regex("(?i)(replace-me|\\.invalid$)", g))])
    error_message = "gcp_overrides.pam_approver_groups entries must be bare group email addresses (placeholders such as REPLACE-ME / .invalid are rejected)."
  }

  validation {
    condition     = can(regex("^[0-9]+s$", var.gcp.pam_max_request_duration)) && tonumber(trimsuffix(var.gcp.pam_max_request_duration, "s")) <= 86400
    error_message = "gcp_overrides.pam_max_request_duration must be '<seconds>s' and at most 86400s (24h)."
  }

  validation {
    condition     = contains(["separate", "organization"], var.gcp.guardrail_owner_mode)
    error_message = "gcp_overrides.guardrail_owner_mode must be \"separate\" or \"organization\"."
  }

  validation {
    condition     = var.gcp.log_analytics_retention_days >= 365 && var.gcp.log_analytics_retention_days <= 3650
    error_message = "gcp_overrides.log_analytics_retention_days must be between 365 and 3650 (audit logs are kept at least a year)."
  }

  validation {
    condition     = var.gcp.logging_settings_kms_key_name == null || can(regex("^projects/.+/locations/.+/keyRings/.+/cryptoKeys/.+$", var.gcp.logging_settings_kms_key_name))
    error_message = "gcp_overrides.logging_settings_kms_key_name must be in format: projects/{project}/locations/{location}/keyRings/{keyring}/cryptoKeys/{key}."
  }

  validation {
    condition     = alltrue([for u in var.gcp.allowed_workload_identity_issuers : can(regex("^https://[a-z0-9.-]+(/.*)?$", u))])
    error_message = "gcp_overrides.allowed_workload_identity_issuers entries must be https:// issuer URIs."
  }

  validation {
    condition     = alltrue([for a in var.gcp.allowed_workload_identity_aws_accounts : can(regex("^[0-9]{12}$", a))])
    error_message = "gcp_overrides.allowed_workload_identity_aws_accounts entries must be 12-digit AWS account IDs."
  }

  validation {
    condition     = alltrue([for c in keys(var.gcp.org_policy_overrides) : can(regex("^[a-zA-Z0-9]+\\.[a-zA-Z0-9.]+$", c))])
    error_message = "gcp_overrides.org_policy_overrides keys must be constraint names such as compute.requireOsLogin (no constraints/ prefix)."
  }

  validation {
    condition     = contains(["enforce", "dry_run", "off"], var.gcp.wif_tenant_pin_enforcement)
    error_message = "gcp_overrides.wif_tenant_pin_enforcement must be enforce, dry_run or off."
  }
}

variable "terraform_admin_email" {
  description = "Email address of the Terraform admin service account"
  type        = string

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.terraform_admin_email))
    error_message = "terraform_admin_email must be a valid email address."
  }
}

variable "billing_account" {
  description = "The GCP billing account ID in format XXXXXX-XXXXXX-XXXXXX"
  type        = string

  validation {
    condition     = can(regex("^[A-Z0-9]{6}-[A-Z0-9]{6}-[A-Z0-9]{6}$", var.billing_account))
    error_message = "billing_account must be a valid GCP billing account ID in format XXXXXX-XXXXXX-XXXXXX."
  }
}

variable "project_prefix" {
  description = "Short prefix applied to all project IDs to ensure global uniqueness (lowercase letters, digits, hyphens; starts with letter)"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.project_prefix))
    error_message = "project_prefix must start with a lowercase letter and contain only lowercase letters, digits, and hyphens."
  }
}

variable "environments" {
  description = "Map of environment definitions keyed by environment name (e.g., dev, staging, prod). is_production (default false) marks production environments for the production guardrail checks."
  type = map(object({
    display_name            = string
    description             = string
    iam_group_role_bindings = map(set(string))
    is_production           = optional(bool, false)
  }))

  validation {
    condition     = length(var.environments) > 0
    error_message = "At least one environment must be defined."
  }
}

variable "default_region" {
  description = "Default GCP region for regional resources (e.g., 'us-central1', 'europe-west1')"
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.default_region))
    error_message = "default_region must be a valid GCP region name (e.g., 'us-central1', 'europe-west1')."
  }
}

variable "monthly_budget_amount" {
  description = "Monthly budget cap in the configured currency. Set to 0 to disable budget alerts (no Budget resource will be created). Must be >= 0."
  type        = number

  validation {
    condition     = var.monthly_budget_amount >= 0
    error_message = "monthly_budget_amount must be 0 (disabled) or a positive number."
  }
}

variable "budget_threshold_rules" {
  description = "Explicit threshold rules for the organization budget (percent is a fraction: 0.5 = 50%; spend_basis CURRENT_SPEND or FORECASTED_SPEND). Null = the billing module defaults (50% / 90% / 100% forecasted / 100% actual). The starter profile passes 50/80/100."
  type = list(object({
    percent     = number
    spend_basis = optional(string, "CURRENT_SPEND")
  }))
  default = null
}

variable "audit_log_retention_days" {
  description = <<-EOT
    Number of days to retain audit logs in Cloud Storage. Adjust to meet your
    compliance requirements:
      - Default (365 days) — sufficient for most cloud security baselines.
      - PCI-DSS requires 12 months online + 12 months archival.
      - HIPAA requires 6 years.
      - FedRAMP requires 3 years.
    Must be >= 1.
  EOT
  type        = number
  default     = 365

  validation {
    condition     = var.audit_log_retention_days >= 1
    error_message = "audit_log_retention_days must be at least 1."
  }
}

# --- Dedicated logging project (opt-in, default = unchanged) ---

# --- Control-plane alerting ---

variable "budget_notify_alert_channels" {
  description = "Attach the control-plane email notification channels to the organization budget, so budget alerts reach the same recipients. Default false (the budget notifies only its Pub/Sub topic). A budget accepts at most 5 channels, so alert_notification_emails plus alert_notification_channels must total 5 or fewer (the plan fails otherwise). The identity that applies the budget needs monitoring.notificationChannels.get on the audit project. Needs enable_control_plane_alerting and alert_notification_emails."
  type        = bool
  default     = false
}

# --- VPC-SC: per-environment scoped access policies ---

variable "shared_folder_key" {
  description = "Key in environments of the shared (hub/DNS) folder. It gets no scoped access policy (the hub perimeter lives in the org-wide policy) and its delegated folder-IAM admits only delegated_network_folder_roles."
  type        = string
  default     = "shared"
}

variable "workload_service_accounts" {
  description = "Map of environment key -> { plan, apply } workload SA emails (gcp-bootstrap output workload_service_accounts). Granted on their own environment's scoped access policy. Default {} = no grants."
  type = map(object({
    plan  = string
    apply = string
  }))
  default = {}

  validation {
    condition     = alltrue([for env, sas in var.workload_service_accounts : can(regex("^[^@]+@[^@]+\\.iam\\.gserviceaccount\\.com$", sas.plan)) && can(regex("^[^@]+@[^@]+\\.iam\\.gserviceaccount\\.com$", sas.apply)) && sas.plan != sas.apply])
    error_message = "Each workload_service_accounts entry needs distinct plan and apply service-account emails (*.iam.gserviceaccount.com)."
  }
}

# --- projects-apply delegated folder-IAM (bound per folder) ---

variable "projects_apply_service_account" {
  description = "Email of the gcp-projects APPLY SA (gcp-bootstrap output stage_service_accounts[\"projects\"].apply). When set, it gets a conditional roles/resourcemanager.folderIamAdmin on each environment folder (delegated_workload_folder_roles only) and on the shared folder (delegated_network_folder_roles only). Null = no delegation."
  type        = string
  default     = null

  validation {
    condition     = var.projects_apply_service_account == null || can(regex("^[^@]+@[^@]+\\.iam\\.gserviceaccount\\.com$", var.projects_apply_service_account))
    error_message = "projects_apply_service_account must be a service-account email (*.iam.gserviceaccount.com) or null."
  }
}

variable "delegated_workload_folder_roles" {
  description = "Roles projects-apply may grant on environment folders (gcp-bootstrap output delegated_workload_folder_roles)."
  type        = list(string)
  default     = []

  validation {
    condition     = length(setintersection(toset(var.delegated_workload_folder_roles), toset(["roles/owner", "roles/resourcemanager.folderAdmin", "roles/resourcemanager.folderIamAdmin", "roles/iam.securityAdmin"]))) == 0
    error_message = "delegated_workload_folder_roles must not contain roles/owner, folderAdmin, folderIamAdmin or iam.securityAdmin (the delegate could escalate)."
  }
}

variable "delegated_network_folder_roles" {
  description = "Roles projects-apply may grant on the shared folder (gcp-bootstrap output delegated_network_folder_roles)."
  type        = list(string)
  default     = []

  validation {
    condition     = length(setintersection(toset(var.delegated_network_folder_roles), toset(["roles/owner", "roles/resourcemanager.folderAdmin", "roles/resourcemanager.folderIamAdmin", "roles/iam.securityAdmin"]))) == 0
    error_message = "delegated_network_folder_roles must not contain roles/owner, folderAdmin, folderIamAdmin or iam.securityAdmin (the delegate could escalate)."
  }
}

# --- Privileged Access Manager: just-in-time org admin ---

variable "pam_entitlement_id" {
  description = "ID of the PAM org-admin entitlement."
  type        = string
  default     = "jit-org-admin"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{3,61}[a-z0-9]$", var.pam_entitlement_id))
    error_message = "pam_entitlement_id must be 5-63 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "pam_roles" {
  description = "Roles granted for the duration of an approved PAM request."
  type        = list(string)
  default     = ["roles/resourcemanager.organizationAdmin"]

  validation {
    condition     = length(var.pam_roles) > 0 && alltrue([for r in var.pam_roles : startswith(r, "roles/") || can(regex("^organizations/[0-9]+/roles/", r))])
    error_message = "pam_roles must be a non-empty list of role names (roles/... or organizations/<id>/roles/...)."
  }
}

variable "pam_notification_emails" {
  description = "Optional extra emails notified of PAM grants (admin_email_recipients)."
  type        = list(string)
  default     = []
}

variable "logging_settings_storage_location" {
  description = "Default storage location for new projects' log buckets. Null = default_region."
  type        = string
  default     = null
}

variable "production_containment_waived" {
  description = "The caller has deliberately decided to run production environments without admin containment, or reports the missing break-glass principal itself. This silences the production_requires_admin_containment warning. The gcp-organization root sets it only for an explicit enable_admin_containment = false. Default false."
  type        = bool
  default     = false
}

variable "wif_tenant_pins" {
  description = "Tenant pins for workload identity pool providers (custom org-policy constraint custom.wifProviderTenantPinned). With tfc_organization set, a provider for https://<tfc_hostname> must reference that organization in its attribute_condition. With github_owner_ids set, a GitHub Actions provider's attribute_condition must be exactly assertion.repository_owner_id == \"<id>\" for one of those IDs (repository, ref and environment pins belong in the principalSet bindings). Both empty (default) creates no constraint. The gcp-organization root fills tfc_organization from config."
  type = object({
    tfc_hostname     = optional(string, "app.terraform.io")
    tfc_organization = optional(string)
    github_owner_ids = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = (var.wif_tenant_pins.tfc_organization == null || can(regex("^[A-Za-z0-9_-]+$", coalesce(var.wif_tenant_pins.tfc_organization, "x")))) && alltrue([for i in var.wif_tenant_pins.github_owner_ids : can(regex("^[0-9]+$", i))])
    error_message = "wif_tenant_pins.tfc_organization must be a literal TFC organization name and github_owner_ids numeric GitHub owner IDs."
  }
}

