# Organization Stage Module

Sets up the organizational hierarchy, policies, and centralized governance features.

## Purpose

- **Hierarchy**: Defines the shared-services folder plus one folder per declared environment
- **IAM**: Configures organization-level access (groups, roles)
- **Governance**: Applies organization policies (boolean & list constraints)
- **Auditing**: Sets up centralized Cloud Audit Logs and BigQuery analytics
- **Security**: Configures SCC notifications and essential contacts

## Dependencies

Requires the `bootstrap` stage to be completed first. The Terraform Admin SA created in bootstrap should be used to apply this module.

## Usage

```hcl
module "organization" {
  source = "../../modules/gcp/stages/organization"

  org_id          = "123456789"
  billing_account = "000000-000000-000000"
  admin_project_id = "my-org-admin-123"

  # Every tuning input sits in one object, the gcp section. Unset keys take
  # the defaults listed in the gcp input below; admin_email is required.
  gcp = {
    admin_email               = "admin@example.com"
    organization_admin_groups = ["gcp-org-admins@example.com"]
    billing_admin_groups      = ["gcp-billing-admins@example.com"]
  }
}
```

The `envs/gcp/organization` root builds `gcp` from `config/landing-zone.yaml`
(`gcp.*`) with its `gcp_overrides` variable on top: a set override key wins, an
unset one keeps the config value, else the default here.

## Key Components

1. **Folder Structure**: shared-services plus a declarative environment map
2. **Org Policies**: Security baselines (no public IPs, shielded VMs, etc.)
3. **Audit Logging**: Long-term storage in GCS + Analytics in BigQuery
4. **SCC**: Real-time security finding notifications

## Outputs

- `folders`: Map of created folders
- `organization_id`: Organization ID
- `tag_keys`: Tag keys exposed to downstream consumers
- `tag_value_ids`: Tag values exposed to downstream consumers

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	admin_project_id =
	admin_project_number =
	billing_account =
	customer_id =
	default_region =
	domain =
	environments =
	monthly_budget_amount =
	org_id =
	project_prefix =
	terraform_admin_email =
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.17, < 2.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 8.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 8.10.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules


- audit_cmek - ../../governance/kms
- audit_logs - ../../governance/cloud-audit-logs
- automation_boundary - ../../iam/principal-access-boundary
- cmek - ../../governance/kms
- control_plane_alerting - ../../monitoring/control-plane
- guardrails - ../guardrails
- iam_deny - ../../iam/deny-policy
- org_budget - ../../governance/billing
- org_policies - ../../governance/org-policy
- organization - ../../iam/organization
- os_login_exemptions - ../../governance/org-policy
- prod_folder_policies - ../../governance/org-policy
- scc_notifications - ../../governance/scc
- tags - ../../governance/tags


## Resources

The following resources are created:


- resource.google_access_context_manager_access_policy.environment (modules/gcp/stages/organization/automation_delegation.tf#L41)
- resource.google_access_context_manager_access_policy_iam_member.environment (modules/gcp/stages/organization/automation_delegation.tf#L49)
- resource.google_bigquery_dataset.billing_export (modules/gcp/stages/organization/main.tf#L723)
- resource.google_bigquery_dataset_iam_member.billing_export_writer (modules/gcp/stages/organization/main.tf#L754)
- resource.google_essential_contacts_contact.billing (modules/gcp/stages/organization/main.tf#L693)
- resource.google_essential_contacts_contact.security (modules/gcp/stages/organization/main.tf#L684)
- resource.google_folder_iam_member.projects_delegated_folder_iam (modules/gcp/stages/organization/automation_delegation.tf#L57)
- resource.google_folder_iam_member.terraform_admin_folder_roles (modules/gcp/stages/organization/main.tf#L45)
- resource.google_logging_organization_settings.this (modules/gcp/stages/organization/main.tf#L661)
- resource.google_privileged_access_manager_entitlement.org_admin (modules/gcp/stages/organization/pam.tf#L10)
- resource.google_tags_location_tag_binding.containment_audit_keyring (modules/gcp/stages/organization/containment.tf#L37)
- resource.google_tags_location_tag_binding.containment_buckets (modules/gcp/stages/organization/containment.tf#L19)
- resource.google_tags_location_tag_binding.containment_log_analytics_bucket (modules/gcp/stages/organization/containment.tf#L29)
- resource.google_tags_tag_binding.environment (modules/gcp/stages/organization/tags_binding.tf#L1)
- resource.terraform_data.budget_channel_limit (modules/gcp/stages/organization/main.tf#L204)
- resource.terraform_data.production_requires_admin_containment (modules/gcp/stages/organization/main.tf#L194)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_admin_project_id"></a> [admin\_project\_id](#input\_admin\_project\_id) | The project ID of the bootstrap admin project | `string` | n/a | yes |
| <a name="input_admin_project_number"></a> [admin\_project\_number](#input\_admin\_project\_number) | The numeric project number of the bootstrap admin project (digits only) | `string` | n/a | yes |
| <a name="input_billing_account"></a> [billing\_account](#input\_billing\_account) | The GCP billing account ID in format XXXXXX-XXXXXX-XXXXXX | `string` | n/a | yes |
| <a name="input_customer_id"></a> [customer\_id](#input\_customer\_id) | The Google Workspace customer ID (format: 'C' followed by alphanumerics, e.g., 'C0abc1234') | `string` | n/a | yes |
| <a name="input_default_region"></a> [default\_region](#input\_default\_region) | Default GCP region for regional resources (e.g., 'us-central1', 'europe-west1') | `string` | n/a | yes |
| <a name="input_domain"></a> [domain](#input\_domain) | The primary domain of the GCP organization (e.g., 'example.com') | `string` | n/a | yes |
| <a name="input_environments"></a> [environments](#input\_environments) | Map of environment definitions keyed by environment name (e.g., dev, staging, prod). is\_production (default false) marks production environments for the production guardrail checks. | <pre>map(object({<br/>    display_name            = string<br/>    description             = string<br/>    iam_group_role_bindings = map(set(string))<br/>    is_production           = optional(bool, false)<br/>  }))</pre> | n/a | yes |
| <a name="input_monthly_budget_amount"></a> [monthly\_budget\_amount](#input\_monthly\_budget\_amount) | Monthly budget cap in the configured currency. Set to 0 to disable budget alerts (no Budget resource will be created). Must be >= 0. | `number` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | The numeric GCP organization ID (digits only, no 'organizations/' prefix) | `string` | n/a | yes |
| <a name="input_project_prefix"></a> [project\_prefix](#input\_project\_prefix) | Short prefix applied to all project IDs to ensure global uniqueness (lowercase letters, digits, hyphens; starts with letter) | `string` | n/a | yes |
| <a name="input_terraform_admin_email"></a> [terraform\_admin\_email](#input\_terraform\_admin\_email) | Email address of the Terraform admin service account | `string` | n/a | yes |
| <a name="input_audit_log_retention_days"></a> [audit\_log\_retention\_days](#input\_audit\_log\_retention\_days) | Number of days to retain audit logs in Cloud Storage. Adjust to meet your<br/>compliance requirements:<br/>  - Default (365 days) — sufficient for most cloud security baselines.<br/>  - PCI-DSS requires 12 months online + 12 months archival.<br/>  - HIPAA requires 6 years.<br/>  - FedRAMP requires 3 years.<br/>Must be >= 1. | `number` | `365` | no |
| <a name="input_budget_notify_alert_channels"></a> [budget\_notify\_alert\_channels](#input\_budget\_notify\_alert\_channels) | Attach the control-plane email notification channels to the organization budget, so budget alerts reach the same recipients. Default false (the budget notifies only its Pub/Sub topic). A budget accepts at most 5 channels, so alert\_notification\_emails plus alert\_notification\_channels must total 5 or fewer (the plan fails otherwise). The identity that applies the budget needs monitoring.notificationChannels.get on the audit project. Needs enable\_control\_plane\_alerting and alert\_notification\_emails. | `bool` | `false` | no |
| <a name="input_budget_threshold_rules"></a> [budget\_threshold\_rules](#input\_budget\_threshold\_rules) | Explicit threshold rules for the organization budget (percent is a fraction: 0.5 = 50%; spend\_basis CURRENT\_SPEND or FORECASTED\_SPEND). Null = the billing module defaults (50% / 90% / 100% forecasted / 100% actual). The starter profile passes 50/80/100. | <pre>list(object({<br/>    percent     = number<br/>    spend_basis = optional(string, "CURRENT_SPEND")<br/>  }))</pre> | `null` | no |
| <a name="input_delegated_network_folder_roles"></a> [delegated\_network\_folder\_roles](#input\_delegated\_network\_folder\_roles) | Roles projects-apply may grant on the shared folder (gcp-bootstrap output delegated\_network\_folder\_roles). | `list(string)` | `[]` | no |
| <a name="input_delegated_workload_folder_roles"></a> [delegated\_workload\_folder\_roles](#input\_delegated\_workload\_folder\_roles) | Roles projects-apply may grant on environment folders (gcp-bootstrap output delegated\_workload\_folder\_roles). | `list(string)` | `[]` | no |
| <a name="input_gcp"></a> [gcp](#input\_gcp) | The gcp section of the organization stage: every tuning input the gcp-organization root takes from config/landing-zone.yaml (gcp.*) or from its gcp\_overrides variable, in one object. Each attribute is documented in the type; an unset (or null) attribute takes the default shown there. admin\_email is required. The root fills enable\_admin\_containment, containment\_exempt\_principals, guardrail\_owner\_mode and allowed\_workload\_identity\_issuers from its own derivations. | <pre>object({<br/>    # Email address of the primary administrator. Granted standing org/billing admin as a user:<br/>    # principal ONLY when allow_user_principals_for_break_glass = true.<br/>    admin_email = optional(string)<br/>    # Optional break-glass emergency user email. Always watched by the CRITICAL break-glass control-<br/>    # plane alert; granted standing org admin ONLY when allow_user_principals_for_break_glass = true<br/>    # (prefer a break-glass group, or the PAM entitlement).<br/>    break_glass_user = optional(string)<br/>    # Google Group email addresses (bare, no 'group:' prefix) granted<br/>    # roles/resourcemanager.organizationAdmin. Standing org admin is group-only: must be non-empty<br/>    # unless allow_user_principals_for_break_glass = true, and must not contain admin_email or<br/>    # break_glass_user (those are users).<br/>    organization_admin_groups = optional(list(string), [])<br/>    # Google Group email addresses (bare, no 'group:' prefix) granted roles/billing.admin. Group-only<br/>    # unless allow_user_principals_for_break_glass = true.<br/>    billing_admin_groups = optional(list(string), [])<br/>    # Escape hatch. When true, admin_email and break_glass_user are ALSO granted standing<br/>    # roles/resourcemanager.organizationAdmin (and admin_email roles/billing.admin) as user:<br/>    # principals. Default false: standing admin goes to groups only; use a break-glass group or the<br/>    # PAM entitlement (enable_pam) for individual elevation.<br/>    allow_user_principals_for_break_glass = optional(bool, false)<br/>    # List of GCP regions permitted by resource location org policy<br/>    allowed_regions = optional(list(string), ["europe-west1", "europe-west2", "us-central1"])<br/>    # Subset of environment keys that enforce strict resource location policies<br/>    strict_folder_policy_environment_keys = optional(list(string), ["prod"])<br/>    # Enforce compute.requireOsLogin at the organization node (CIS GCP 4.4), so every VM in every<br/>    # folder must use OS Login. Exempt folders via os_login_exempt_environment_keys. Default true.<br/>    enforce_os_login = optional(bool, true)<br/>    # Environment folder keys exempted from the org-wide OS Login requirement (a folder-level<br/>    # compute.requireOsLogin = false override). Keys in strict_folder_policy_environment_keys cannot<br/>    # be exempted. Default [] = no exemptions.<br/>    os_login_exempt_environment_keys = optional(list(string), [])<br/>    # Email address for security notifications via Essential Contacts (SCC alerts, compliance<br/>    # notifications). Optional — if null, no Essential Contact is registered for the SECURITY<br/>    # category.<br/>    security_contact_email = optional(string)<br/>    # Email address for billing notifications and budget alerts via Essential Contacts. Optional — if<br/>    # null, no Essential Contact is registered for the BILLING category.<br/>    billing_contact_email = optional(string)<br/>    # ISO 4217 currency code for the budget (e.g., USD, EUR, GBP)<br/>    budget_currency = optional(string, "USD")<br/>    # Dedicated logging project ID for the org audit sink, audit bucket, BigQuery audit dataset, audit<br/>    # CMEK keyring and control-plane alerts (separation of duties). Default null = the admin/bootstrap<br/>    # project (unchanged). The project MUST NOT be owned (roles/owner, roles/editor, or storage/KMS<br/>    # admin) by the Terraform admin / automation service account — otherwise the identity being<br/>    # audited can delete object generations or destroy the key protecting its own audit trail. Create<br/>    # it out-of-band (or from a separate identity) and grant the automation SA only what it needs to<br/>    # manage the resources here. Decide BEFORE the first apply: KMS keys cannot be deleted, so moving<br/>    # the audit keys later orphans the old ones. Requires logging_project_number. PREVIEW: not yet<br/>    # validated against a real apply.<br/>    logging_project_id = optional(string)<br/>    # Numeric project number of logging_project_id (required when it is set). Used to grant the<br/>    # logging project's GCS and BigQuery service agents access to the audit CMEK keys.<br/>    logging_project_number = optional(string)<br/>    # Soft-delete window (days) on the org audit-log buckets: deleted/overwritten objects stay<br/>    # restorable for this long. 7-90, or 0 to disable. Default 30.<br/>    audit_soft_delete_retention_days = optional(number, 30)<br/>    # Create log-match alerts on control-plane changes (org IAM, org policy, VPC-SC, sinks/exclusions,<br/>    # custom roles, deny policies, KMS key-version destroy/disable, tag binding/key/value deletion)<br/>    # and on break-glass use, in the audit/logging project. Default true.<br/>    enable_control_plane_alerting = optional(bool, true)<br/>    # With enable_control_plane_alerting, also create the CIS GCP 2.4-2.11 log-based metrics and alert<br/>    # policies (project ownership, audit config, custom roles, firewall rules, routes, networks, Cloud<br/>    # Storage IAM, Cloud SQL config) in the audit/logging project. The aggregated org sink feeds them<br/>    # every project's Admin Activity logs, so one set covers the org. Default true.<br/>    enable_cis_log_metrics = optional(bool, true)<br/>    # Email addresses notified by the control-plane alerts (one email channel each). Default [] — a<br/>    # check warns if no destination is set.<br/>    alert_notification_emails = optional(list(string), [])<br/>    # IDs of existing Cloud Monitoring notification channels (projects/<p>/notificationChannels/<id>)<br/>    # attached to every control-plane alert. Default [].<br/>    alert_notification_channels = optional(list(string), [])<br/>    # Extra break-glass principal emails (users/SAs) whose ANY admin action raises a CRITICAL control-<br/>    # plane alert. break_glass_user is always included. Group membership is not visible in audit logs,<br/>    # so list the member accounts of a break-glass group here.<br/>    break_glass_principal_emails = optional(list(string), [])<br/>    # Opt-in custom organization-policy constraints (CEL-defined resource-shape guardrails), created<br/>    # AND enforced at the org node (enforcement = enforce | dry_run | off; dry_run logs violations<br/>    # without blocking, the way to stage a new one). Default [] = none. See docs/known-gaps.md.<br/>    custom_org_constraints = optional(list(object({<br/>      name           = string<br/>      display_name   = string<br/>      description    = string<br/>      action_type    = string<br/>      condition      = string<br/>      method_types   = list(string)<br/>      resource_types = list(string)<br/>      enforcement    = optional(string, "enforce")<br/>    })), [])<br/>    # Opt-in WORM lock on the org audit-log GCS bucket (a locked retention policy of<br/>    # audit_log_retention_days). Default false preserves the current behaviour (versioned + access-<br/>    # controlled but not immutable, and a lifecycle delete that can be corrected). Enable only for<br/>    # compliance regimes that require tamper-proof retention — a locked policy CANNOT be shortened or<br/>    # removed. See docs/known-gaps.md.<br/>    enable_audit_bucket_lock = optional(bool, false)<br/>    # Opt-in IAM deny policies applied at the org node — a coarse, allow-independent backstop that<br/>    # blocks specific permissions for specific principals regardless of roles held (deny is evaluated<br/>    # before allow). Default [] = none. See docs/known-gaps.md.<br/>    iam_deny_policies = optional(list(object({<br/>      name         = string<br/>      display_name = optional(string)<br/>      rules = list(object({<br/>        description           = optional(string)<br/>        denied_principals     = list(string)<br/>        denied_permissions    = list(string)<br/>        exception_principals  = optional(list(string), [])<br/>        exception_permissions = optional(list(string), [])<br/>        denial_condition = optional(object({<br/>          expression  = string<br/>          title       = optional(string)<br/>          description = optional(string)<br/>        }))<br/>      }))<br/>    })), [])<br/>    # Enforce CMEK on sensitive services org-wide via the gcp.restrictNonCmekServices org policy.<br/>    # Default false, so a default apply is unchanged; the prod-hardening preset turns it on. Enabling<br/>    # denies creating resources in cmek_required_services without a customer-managed key, so wire CMEK<br/>    # keys for those services first.<br/>    enable_cmek_org_policy = optional(bool, false)<br/>    # Services that require CMEK when enable_cmek_org_policy is true. Admins tune this list.<br/>    cmek_required_services = optional(list(string), [<br/>      "storage.googleapis.com",<br/>      "bigquery.googleapis.com",<br/>      "sqladmin.googleapis.com",<br/>      "spanner.googleapis.com",<br/>      "pubsub.googleapis.com",<br/>      "secretmanager.googleapis.com",<br/>    ])<br/>    # IAM deny policy at the org node that blocks, for all principals except<br/>    # containment_exempt_principals (break-glass): org-wide update/delete of logging sinks, exclusion<br/>    # changes, log-bucket delete, VPC-SC perimeter update/delete/replaceAll/commit and access-policy<br/>    # delete; and, scoped by the containment/protected tag to the audit buckets + audit CMEK keyring,<br/>    # bucket delete/setIamPolicy/deleteTagBinding, object delete, key-version destroy/update (disable)<br/>    # and key setIamPolicy. Once on, Terraform changes to ANY sink, exclusion or perimeter must run as<br/>    # break-glass. Default false at this stage; the gcp-organization root derives it ON whenever an<br/>    # environment is_production (and fails the plan without a break-glass principal). In<br/>    # guardrail_owner_mode = "separate" this stage only creates and binds the containment/protected<br/>    # tag; the gcp-guardrails root applies the policy itself.<br/>    enable_admin_containment = optional(bool, false)<br/>    # Break-glass principals exempt from the admin-containment deny policy, e.g.<br/>    # ["principalSet://goog/group/break-glass@example.com"]. Required (non-empty) when<br/>    # enable_admin_containment is true.<br/>    containment_exempt_principals = optional(list(string), [])<br/>    # Grant the phase-0 bootstrap SA (terraform_admin_email)<br/>    # folderAdmin/projectCreator/billing.projectManager/networkAdmin on every folder. Legacy single-<br/>    # identity model; default false because the per-stage plan/apply service accounts replace it.<br/>    # Enable only while migrating an existing deployment.<br/>    enable_legacy_admin_folder_roles = optional(bool, false)<br/>    # Create one folder-scoped Access Context Manager policy per environment folder (every key in<br/>    # environments except shared_folder_key) and grant that environment's workload SAs<br/>    # (workload_service_accounts) policyEditor (apply) / policyReader (plan) on it only. The workload<br/>    # root builds its perimeter in this policy. Requires the gcp-bootstrap<br/>    # enable_scoped_access_policies input (policyAdmin for the organization apply SA). Default true.<br/>    enable_scoped_access_policies = optional(bool, true)<br/>    # Create a Privileged Access Manager entitlement at the org node: members of pam_eligible_groups<br/>    # may request pam_roles for up to pam_max_request_duration, with justification, approved by<br/>    # pam_approver_groups. Requires the gcp-bootstrap enable_pam input. Default false.<br/>    enable_pam = optional(bool, false)<br/>    # Bare group emails whose members may request the PAM entitlement. Required when enable_pam =<br/>    # true.<br/>    pam_eligible_groups = optional(list(string), [])<br/>    # Bare group emails whose members approve PAM requests. Required when enable_pam = true; keep it<br/>    # disjoint from pam_eligible_groups so nobody approves their own request.<br/>    pam_approver_groups = optional(list(string), [])<br/>    # Maximum duration of a PAM grant, in seconds with an 's' suffix (e.g. 3600s). Default 1 hour.<br/>    pam_max_request_duration = optional(string, "3600s")<br/>    # Who applies the org IAM deny policies (admin containment + iam_deny_policies). "separate"<br/>    # (default): this stage neither builds nor applies them (its apply identity has no<br/>    # roles/iam.denyAdmin, so it cannot delete the containment policy that constrains it); the gcp-<br/>    # guardrails root authors them from config and applies them as the gcp-bootstrap<br/>    # <prefix>-guardrails-apply SA. This stage still creates and binds the containment tag.<br/>    # "organization": legacy, this stage applies them (needs gcp-bootstrap guardrail_owner_mode =<br/>    # "organization"). Migrating from organization to separate: terraform state rm the module.iam_deny<br/>    # resources here and import them into gcp-guardrails (UPGRADING.md).<br/>    guardrail_owner_mode = optional(string, "separate")<br/>    # Set every baseline org-policy constraint that has a like-for-like managed successor<br/>    # (constraints/*.managed.*: service-account key creation/upload, default-SA basic roles, serial<br/>    # port, OS Login, nested virtualization, guest attributes, VM external IPs, Cloud SQL public IP)<br/>    # through the managed version. Default true. Constraints without a managed equivalent (and<br/>    # iam.allowedPolicyMemberDomains, see docs/known-gaps.md) stay legacy.<br/>    prefer_managed_constraints = optional(bool, true)<br/>    # Route every org audit log into a Log Analytics-enabled Cloud Logging bucket in the audit<br/>    # project, with a linked read-only BigQuery dataset. Default true.<br/>    enable_log_analytics = optional(bool, true)<br/>    # Retention (days) of the audit Log Analytics bucket. Locked (irreversibly) together with the GCS<br/>    # audit bucket when enable_audit_bucket_lock = true.<br/>    log_analytics_retention_days = optional(number, 400)<br/>    # Manage the organization's Cloud Logging settings (google_logging_organization_settings): the<br/>    # storage location of the _Default/_Required buckets of new projects<br/>    # (logging_settings_storage_location, default default_region) and optionally their CMEK<br/>    # (logging_settings_kms_key_name). Default false.<br/>    enable_logging_organization_settings = optional(bool, false)<br/>    # SCC API generation for the notification stream: v1 (default, unchanged), both (add the v2 twin<br/>    # next to v1 to verify), or v2 (flip; v1 configs destroyed). See docs/runbooks/scc-v2-migration.md.<br/>    scc_api_version = optional(string, "v1")<br/>    # With enable_logging_organization_settings: disable the organization's _Default log sink, so new<br/>    # projects stop routing org-level logs into the _Default bucket. Default false (unchanged). Only<br/>    # the audit-log sinks (cloudaudit) are routed centrally, so enable it only after confirming the<br/>    # non-audit org logs you need are covered by another sink.<br/>    disable_default_sink = optional(bool, false)<br/>    # Optional CMEK for the _Default/_Required buckets of new projects. Grant the org Cloud Logging<br/>    # service account (gcloud logging settings describe --organization=<id>)<br/>    # roles/cloudkms.cryptoKeyEncrypterDecrypter on the key first. Null = Google-managed encryption.<br/>    logging_settings_kms_key_name = optional(string)<br/>    # Bind a principal access boundary policy to every service account in the admin (automation)<br/>    # project, so their permissions only work on resources in this organization (plus<br/>    # principal_access_boundary_allowed_resources). Needs the gcp-bootstrap<br/>    # enable_principal_access_boundary input. With enable_admin_containment the boundary's<br/>    # update/delete/unbind is also denied to all but break-glass. Default false: validate on a non-<br/>    # production org first.<br/>    enable_principal_access_boundary = optional(bool, false)<br/>    # Resources the bounded automation SAs may act on<br/>    # (//cloudresourcemanager.googleapis.com/organizations|folders|projects/<id>). Empty = this<br/>    # organization only.<br/>    principal_access_boundary_allowed_resources = optional(list(string), [])<br/>    # Enforce run.allowedIngress org-wide so Cloud Run services accept only internal or Cloud Load<br/>    # Balancing traffic (never ingress "all"). Public apps are served through the external ALB + Cloud<br/>    # Armor. Default true.<br/>    restrict_cloud_run_ingress = optional(bool, true)<br/>    # OIDC issuer URIs a workload identity pool provider may be created for (org policy<br/>    # iam.workloadIdentityPoolProviders). Default: HCP Terraform dynamic credentials and GitHub<br/>    # Actions (app-services deploy identities). Add https://gitlab.com (or your TFE / GitLab host)<br/>    # when used. Empty denies every new provider.<br/>    allowed_workload_identity_issuers = optional(list(string), ["https://app.terraform.io", "https://token.actions.githubusercontent.com"])<br/>    # AWS account IDs a workload identity pool may federate (org policy<br/>    # iam.workloadIdentityPoolAwsAccounts). Empty (default) denies AWS-account federation.<br/>    allowed_workload_identity_aws_accounts = optional(list(string), [])<br/>    # Per-constraint overrides of the organization-policy baseline, keyed by constraint name (e.g.<br/>    # compute.requireOsLogin). For a boolean constraint set enforce. For a list constraint set<br/>    # allowed_values / denied_values / allow_all / deny_all, which replace the baseline values.<br/>    # disabled = true drops the constraint from the baseline. A constraint not in the baseline is<br/>    # added. Use this instead of forking the stage when a single guardrail does not fit.<br/>    org_policy_overrides = optional(map(object({<br/>      enforce        = optional(bool)<br/>      allowed_values = optional(list(string))<br/>      denied_values  = optional(list(string))<br/>      allow_all      = optional(bool)<br/>      deny_all       = optional(bool)<br/>      disabled       = optional(bool, false)<br/>    })), {})<br/>    # How custom.wifProviderTenantPinned is applied: enforce (default; providers that do not pin the<br/>    # tenant are rejected), dry_run (violations are only logged: stage it this way on an org with<br/>    # existing providers), or off.<br/>    wif_tenant_pin_enforcement = optional(string, "enforce")<br/>  })</pre> | `{}` | no |
| <a name="input_logging_settings_storage_location"></a> [logging\_settings\_storage\_location](#input\_logging\_settings\_storage\_location) | Default storage location for new projects' log buckets. Null = default\_region. | `string` | `null` | no |
| <a name="input_pam_entitlement_id"></a> [pam\_entitlement\_id](#input\_pam\_entitlement\_id) | ID of the PAM org-admin entitlement. | `string` | `"jit-org-admin"` | no |
| <a name="input_pam_notification_emails"></a> [pam\_notification\_emails](#input\_pam\_notification\_emails) | Optional extra emails notified of PAM grants (admin\_email\_recipients). | `list(string)` | `[]` | no |
| <a name="input_pam_roles"></a> [pam\_roles](#input\_pam\_roles) | Roles granted for the duration of an approved PAM request. | `list(string)` | <pre>[<br/>  "roles/resourcemanager.organizationAdmin"<br/>]</pre> | no |
| <a name="input_production_containment_waived"></a> [production\_containment\_waived](#input\_production\_containment\_waived) | The caller has deliberately decided to run production environments without admin containment, or reports the missing break-glass principal itself. This silences the production\_requires\_admin\_containment warning. The gcp-organization root sets it only for an explicit enable\_admin\_containment = false. Default false. | `bool` | `false` | no |
| <a name="input_projects_apply_service_account"></a> [projects\_apply\_service\_account](#input\_projects\_apply\_service\_account) | Email of the gcp-projects APPLY SA (gcp-bootstrap output stage\_service\_accounts["projects"].apply). When set, it gets a conditional roles/resourcemanager.folderIamAdmin on each environment folder (delegated\_workload\_folder\_roles only) and on the shared folder (delegated\_network\_folder\_roles only). Null = no delegation. | `string` | `null` | no |
| <a name="input_shared_folder_key"></a> [shared\_folder\_key](#input\_shared\_folder\_key) | Key in environments of the shared (hub/DNS) folder. It gets no scoped access policy (the hub perimeter lives in the org-wide policy) and its delegated folder-IAM admits only delegated\_network\_folder\_roles. | `string` | `"shared"` | no |
| <a name="input_wif_tenant_pins"></a> [wif\_tenant\_pins](#input\_wif\_tenant\_pins) | Tenant pins for workload identity pool providers (custom org-policy constraint custom.wifProviderTenantPinned). With tfc\_organization set, a provider for https://<tfc\_hostname> must reference that organization in its attribute\_condition. With github\_owner\_ids set, a GitHub Actions provider's attribute\_condition must be exactly assertion.repository\_owner\_id == "<id>" for one of those IDs (repository, ref and environment pins belong in the principalSet bindings). Both empty (default) creates no constraint. The gcp-organization root fills tfc\_organization from config. | <pre>object({<br/>    tfc_hostname     = optional(string, "app.terraform.io")<br/>    tfc_organization = optional(string)<br/>    github_owner_ids = optional(list(string), [])<br/>  })</pre> | `{}` | no |
| <a name="input_workload_service_accounts"></a> [workload\_service\_accounts](#input\_workload\_service\_accounts) | Map of environment key -> { plan, apply } workload SA emails (gcp-bootstrap output workload\_service\_accounts). Granted on their own environment's scoped access policy. Default {} = no grants. | <pre>map(object({<br/>    plan  = string<br/>    apply = string<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_admin_containment_rules"></a> [admin\_containment\_rules](#output\_admin\_containment\_rules) | Rules of the admin-containment IAM deny policy this stage applies (legacy guardrail\_owner\_mode = "organization" only; empty in separate mode, where the gcp-guardrails root owns the policy, and when enable\_admin\_containment = false): denied permissions, exempt principals and whether the rule is tag-scoped to the audit store. |
| <a name="output_audit_logs_bucket_name"></a> [audit\_logs\_bucket\_name](#output\_audit\_logs\_bucket\_name) | Name of the Cloud Storage bucket receiving audit logs |
| <a name="output_audit_org_sink_name"></a> [audit\_org\_sink\_name](#output\_audit\_org\_sink\_name) | Name of the org-level audit-log sink that exports to the audit bucket |
| <a name="output_audit_project_id"></a> [audit\_project\_id](#output\_audit\_project\_id) | Project holding the org audit bucket, audit CMEK and control-plane alerts (logging\_project\_id, or the admin project when unset) |
| <a name="output_billing_admin_members"></a> [billing\_admin\_members](#output\_billing\_admin\_members) | Principals holding standing roles/billing.admin (groups only unless allow\_user\_principals\_for\_break\_glass = true). |
| <a name="output_billing_export_dataset_id"></a> [billing\_export\_dataset\_id](#output\_billing\_export\_dataset\_id) | BigQuery dataset ID for Cloud Billing export data |
| <a name="output_cmek_key_names"></a> [cmek\_key\_names](#output\_cmek\_key\_names) | Map of KMS key short names to fully qualified key resource IDs created by the CMEK modules (org keyring plus, when logging\_project\_id is set, the audit keyring in the logging project) |
| <a name="output_containment_tag"></a> [containment\_tag](#output\_containment\_tag) | The containment/protected tag that scopes the audit-store rule of the containment deny policy (null IDs when enable\_admin\_containment = false). The gcp-guardrails root looks it up by these short names under the organization. |
| <a name="output_control_plane_alert_policy_ids"></a> [control\_plane\_alert\_policy\_ids](#output\_control\_plane\_alert\_policy\_ids) | Map of control-plane watch name to alert policy ID (empty when enable\_control\_plane\_alerting = false) |
| <a name="output_control_plane_cis_log_metric_names"></a> [control\_plane\_cis\_log\_metric\_names](#output\_control\_plane\_cis\_log\_metric\_names) | Map of CIS GCP 2.4-2.11 log-metric key to log-based metric name in the alerting project (empty when disabled) |
| <a name="output_control_plane_org_log_route_sink_name"></a> [control\_plane\_org\_log\_route\_sink\_name](#output\_control\_plane\_org\_log\_route\_sink\_name) | Aggregated org sink routing Admin Activity logs to the alerting project (null when alerting is off) |
| <a name="output_control_plane_watched_names"></a> [control\_plane\_watched\_names](#output\_control\_plane\_watched\_names) | Names of the active control-plane alert watches |
| <a name="output_delegated_folder_iam_targets"></a> [delegated\_folder\_iam\_targets](#output\_delegated\_folder\_iam\_targets) | Folders on which projects-apply holds the conditional folderIamAdmin, keyed by folder key, with the role allow-list of each. |
| <a name="output_folders"></a> [folders](#output\_folders) | Map of created folders |
| <a name="output_guardrail_deny_policy_specs"></a> [guardrail\_deny\_policy\_specs](#output\_guardrail\_deny\_policy\_specs) | DEPRECATED (removed in v1.0). Map of deny-policy ID => gcloud policy-file JSON for the deny policies this stage applies in the legacy organization mode. Always empty in separate mode: the gcp-guardrails root owns the policies and exposes the break-glass specs as its deny\_policy\_specs output. |
| <a name="output_guardrail_owner_mode"></a> [guardrail\_owner\_mode](#output\_guardrail\_owner\_mode) | Deny-policy ownership mode: "separate" (deny policies authored and applied by the gcp-guardrails root) or "organization" (legacy: applied by this stage). |
| <a name="output_iam_deny_policy_names"></a> [iam\_deny\_policy\_names](#output\_iam\_deny\_policy\_names) | Names of the IAM deny policies planned at the org node (containment + iam\_deny\_policies) |
| <a name="output_log_analytics_bucket_id"></a> [log\_analytics\_bucket\_id](#output\_log\_analytics\_bucket\_id) | Full ID of the audit Log Analytics bucket (null when disabled). |
| <a name="output_log_analytics_linked_dataset"></a> [log\_analytics\_linked\_dataset](#output\_log\_analytics\_linked\_dataset) | Linked BigQuery dataset on the audit Log Analytics bucket (null when disabled). |
| <a name="output_logging_organization_service_account"></a> [logging\_organization\_service\_account](#output\_logging\_organization\_service\_account) | The org's Cloud Logging service account (grant it the CMEK key before setting logging\_settings\_kms\_key\_name); null when enable\_logging\_organization\_settings = false. |
| <a name="output_managed_org_policy_constraints"></a> [managed\_org\_policy\_constraints](#output\_managed\_org\_policy\_constraints) | Managed constraints (constraints/*.managed.*) set at the org node. |
| <a name="output_org_admin_members"></a> [org\_admin\_members](#output\_org\_admin\_members) | Principals holding standing roles/resourcemanager.organizationAdmin (groups only unless allow\_user\_principals\_for\_break\_glass = true). |
| <a name="output_org_policy_constraints"></a> [org\_policy\_constraints](#output\_org\_policy\_constraints) | Org-node policy constraints this stage manages (legacy boolean + list and managed), for downstream verification |
| <a name="output_organization_id"></a> [organization\_id](#output\_organization\_id) | Organization ID |
| <a name="output_os_login_exempt_environment_keys"></a> [os\_login\_exempt\_environment\_keys](#output\_os\_login\_exempt\_environment\_keys) | Environment folders exempted from the org-wide OS Login requirement (empty when none, or when enforce\_os\_login = false) |
| <a name="output_pam_entitlement_name"></a> [pam\_entitlement\_name](#output\_pam\_entitlement\_name) | Resource name of the just-in-time org-admin PAM entitlement (null when enable\_pam = false). |
| <a name="output_principal_access_boundary_policy"></a> [principal\_access\_boundary\_policy](#output\_principal\_access\_boundary\_policy) | Name of the automation principal access boundary policy (null when disabled). |
| <a name="output_production_environment_keys"></a> [production\_environment\_keys](#output\_production\_environment\_keys) | Environment keys marked is\_production = true. |
| <a name="output_scc_pubsub_topic_id"></a> [scc\_pubsub\_topic\_id](#output\_scc\_pubsub\_topic\_id) | Pub/Sub topic ID receiving Security Command Center findings notifications |
| <a name="output_scc_v2_notification_configs"></a> [scc\_v2\_notification\_configs](#output\_scc\_v2\_notification\_configs) | SCC v2 notification configs (name and service account per config; empty unless gcp.scc\_api\_version is both or v2). Used to verify the v2 publisher binding during the v1 to v2 migration. |
| <a name="output_scoped_access_policy_grants"></a> [scoped\_access\_policy\_grants](#output\_scoped\_access\_policy\_grants) | Workload SA grants on the scoped access policies, keyed "<env>\|<phase>": { env, role, member }. |
| <a name="output_scoped_access_policy_ids"></a> [scoped\_access\_policy\_ids](#output\_scoped\_access\_policy\_ids) | Map of environment key -> numeric ID of its folder-scoped Access Context Manager policy (empty when enable\_scoped\_access\_policies = false). gcp-projects surfaces it as environment\_config[<env>].vpc\_sc\_access\_policy\_id for the workload perimeter. |
| <a name="output_strict_folder_policy_environment_keys"></a> [strict\_folder\_policy\_environment\_keys](#output\_strict\_folder\_policy\_environment\_keys) | Environment folders that received the strict folder org-policy bundle |
| <a name="output_tag_keys"></a> [tag\_keys](#output\_tag\_keys) | Tag keys available to downstream consumers |
| <a name="output_tag_value_ids"></a> [tag\_value\_ids](#output\_tag\_value\_ids) | Tag values available to downstream consumers |
<!-- END_TF_DOCS -->
