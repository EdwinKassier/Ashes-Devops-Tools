# Organization Root

`envs/gcp/organization` is the control-plane root for the platform. It creates the admin project, organization/folder policy, shared hub projects, per-environment host projects, and the downstream contract consumed by `envs/gcp/workload`.

## What It Creates

- One admin project for Terraform automation and workload identity
- One shared services folder containing the hub and DNS projects
- One folder and host project per entry in `var.environments`
- Centralized org policy, audit logging, tags, and platform budgets

## Source Of Truth

Application environments are declared once through `var.environments`. Each entry must provide:

- `display_name`
- `region`
- `cidr_block`
- `budget_monthly_limit`
- `iam_group_role_bindings`
- `labels`

See [`terraform.tfvars.example`](./terraform.tfvars.example) for the expected shape.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.0 |
| <a name="requirement_google-beta"></a> [google-beta](#requirement\_google-beta) | ~> 7.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.31.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules


- organization - ../../../modules/gcp/stages/organization


## Resources

The following resources are created:


- data source.google_billing_account.billing (envs/gcp/organization/data.tf#L33)
- data source.google_organization.org (envs/gcp/organization/data.tf#L27)
- data source.terraform_remote_state.gcp_bootstrap (envs/gcp/organization/data.tf#L15)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_admin_email"></a> [admin\_email](#input\_admin\_email) | Email address for the organization administrator. Null = gcp.admin\_email from config/landing-zone.yaml. | `string` | `null` | no |
| <a name="input_alert_notification_channels"></a> [alert\_notification\_channels](#input\_alert\_notification\_channels) | Existing Cloud Monitoring notification channel IDs (projects/<p>/notificationChannels/<id>) attached to every control-plane alert. Default []. | `list(string)` | `[]` | no |
| <a name="input_alert_notification_emails"></a> [alert\_notification\_emails](#input\_alert\_notification\_emails) | Email addresses notified by the control-plane alerts. Empty (default) = gcp.alert\_emails from config/landing-zone.yaml; a check warns when no destination is set. | `list(string)` | `[]` | no |
| <a name="input_allow_user_principals_for_break_glass"></a> [allow\_user\_principals\_for\_break\_glass](#input\_allow\_user\_principals\_for\_break\_glass) | Escape hatch: also grant admin\_email and break\_glass\_user standing Organization Admin (admin\_email also Billing Admin) as user: principals. Default false (groups only); prefer a break-glass group or enable\_pam. | `bool` | `false` | no |
| <a name="input_allowed_regions"></a> [allowed\_regions](#input\_allowed\_regions) | List of allowed GCP regions for resource creation. Null = gcp.allowed\_regions from config/landing-zone.yaml, else europe-west1/europe-west2/us-central1. | `list(string)` | `null` | no |
| <a name="input_allowed_workload_identity_aws_accounts"></a> [allowed\_workload\_identity\_aws\_accounts](#input\_allowed\_workload\_identity\_aws\_accounts) | AWS account IDs workload identity pools may federate (iam.workloadIdentityPoolAwsAccounts). Empty (default) denies AWS-account federation. | `list(string)` | `[]` | no |
| <a name="input_allowed_workload_identity_issuers"></a> [allowed\_workload\_identity\_issuers](#input\_allowed\_workload\_identity\_issuers) | OIDC issuers workload identity pool providers may trust (org policy iam.workloadIdentityPoolProviders). Null = https://<tfc\_hostname> plus GitHub Actions. Add GitLab / TFE hosts when used. | `list(string)` | `null` | no |
| <a name="input_audit_soft_delete_retention_days"></a> [audit\_soft\_delete\_retention\_days](#input\_audit\_soft\_delete\_retention\_days) | Soft-delete window (days) on the org audit-log buckets (M-4). 7-90, or 0 to disable. Default 30. | `number` | `30` | no |
| <a name="input_billing_account"></a> [billing\_account](#input\_billing\_account) | Billing account ID (optional if billing\_account\_display\_name is provided). Null = gcp.billing\_account from config/landing-zone.yaml. | `string` | `null` | no |
| <a name="input_billing_account_display_name"></a> [billing\_account\_display\_name](#input\_billing\_account\_display\_name) | Display name of the billing account (used if billing\_account ID is not provided) | `string` | `null` | no |
| <a name="input_billing_admin_groups"></a> [billing\_admin\_groups](#input\_billing\_admin\_groups) | Bare group emails granted Billing Admin. At least one is required unless allow\_user\_principals\_for\_break\_glass = true. Null = gcp.billing\_admin\_groups from config/landing-zone.yaml, else []. | `list(string)` | `null` | no |
| <a name="input_billing_contact_email"></a> [billing\_contact\_email](#input\_billing\_contact\_email) | Email for billing notifications via Essential Contacts (optional) | `string` | `null` | no |
| <a name="input_bootstrap_contract"></a> [bootstrap\_contract](#input\_bootstrap\_contract) | gcp-bootstrap stage contract: admin\_project\_id, admin\_project\_number and terraform\_admin\_email, plus the optional automation identities (workload\_service\_accounts, stage\_service\_accounts, delegated\_workload/network\_folder\_roles; omitted = no grants) and guardrail\_owner\_mode. Null = gcp.contracts.bootstrap from config/landing-zone.yaml, else read from the gcp-bootstrap workspace's remote state. | <pre>object({<br/>    admin_project_id                = string<br/>    admin_project_number            = string<br/>    terraform_admin_email           = string<br/>    workload_service_accounts       = optional(map(object({ plan = string, apply = string })), {})<br/>    stage_service_accounts          = optional(map(object({ plan = string, apply = string })), {})<br/>    delegated_workload_folder_roles = optional(list(string), [])<br/>    delegated_network_folder_roles  = optional(list(string), [])<br/>    guardrail_owner_mode            = optional(string, "separate")<br/>  })</pre> | `null` | no |
| <a name="input_bootstrap_workspace_name"></a> [bootstrap\_workspace\_name](#input\_bootstrap\_workspace\_name) | Name of the gcp-bootstrap TFC workspace this root reads via remote state for the admin project, Terraform admin SA, and WIF pools. | `string` | `"gcp-bootstrap"` | no |
| <a name="input_break_glass_principal_emails"></a> [break\_glass\_principal\_emails](#input\_break\_glass\_principal\_emails) | Extra break-glass account emails whose admin actions raise a CRITICAL alert (break\_glass\_user is always included). List the members of a break-glass group here — group membership is not visible in audit logs. | `list(string)` | `[]` | no |
| <a name="input_break_glass_user"></a> [break\_glass\_user](#input\_break\_glass\_user) | Email address for the break glass user (optional). Always watched by the break-glass alert; granted Organization Admin only when allow\_user\_principals\_for\_break\_glass = true. | `string` | `null` | no |
| <a name="input_budget_currency"></a> [budget\_currency](#input\_budget\_currency) | ISO 4217 currency code for budget alerts (e.g., USD, EUR, GBP) | `string` | `"USD"` | no |
| <a name="input_cmek_required_services"></a> [cmek\_required\_services](#input\_cmek\_required\_services) | Services that require CMEK when enable\_cmek\_org\_policy is true. | `list(string)` | <pre>[<br/>  "storage.googleapis.com",<br/>  "bigquery.googleapis.com",<br/>  "sqladmin.googleapis.com",<br/>  "spanner.googleapis.com",<br/>  "pubsub.googleapis.com",<br/>  "secretmanager.googleapis.com"<br/>]</pre> | no |
| <a name="input_containment_exempt_principals"></a> [containment\_exempt\_principals](#input\_containment\_exempt\_principals) | Break-glass principals exempt from the admin-containment deny policy, as IAM v2 principal identifiers (e.g. principalSet://goog/group/break-glass@acme.com). Empty (default) = principalSet://goog/group/<gcp.break\_glass\_group> from config. Required (non-empty) when containment is on. Placeholder values (REPLACE-ME, your-domain, example.com, .invalid) are rejected so a copied preset fails loudly. | `list(string)` | `[]` | no |
| <a name="input_custom_org_constraints"></a> [custom\_org\_constraints](#input\_custom\_org\_constraints) | Opt-in custom organization-policy constraints (CEL-defined resource-shape guardrails), created AND enforced at the org node (enforcement = enforce \| dry\_run \| off). Default [] = none. See docs/known-gaps.md. | <pre>list(object({<br/>    name           = string<br/>    display_name   = string<br/>    description    = string<br/>    action_type    = string<br/>    condition      = string<br/>    method_types   = list(string)<br/>    resource_types = list(string)<br/>    enforcement    = optional(string, "enforce")<br/>  }))</pre> | `[]` | no |
| <a name="input_default_region"></a> [default\_region](#input\_default\_region) | Default region for resources. Null = org.regions.gcp from config/landing-zone.yaml, else europe-west2. | `string` | `null` | no |
| <a name="input_domain"></a> [domain](#input\_domain) | The domain name of the organization (e.g., 'example.com'). Null = org.domain from config/landing-zone.yaml. | `string` | `null` | no |
| <a name="input_enable_admin_containment"></a> [enable\_admin\_containment](#input\_enable\_admin\_containment) | IAM deny policy blocking (for all but containment\_exempt\_principals) org-wide sink update/delete, exclusion changes, log-bucket delete and VPC-SC perimeter update/delete, plus — tag-scoped to the audit store — bucket delete/IAM change/untag, object delete, key-version destroy/disable and key IAM change. Once on, any sink/exclusion/perimeter change must be applied by break-glass. Null (default) = gcp.admin\_containment from config, else ON whenever an environment is\_production. Needs a break-glass principal (gcp.break\_glass\_group or containment\_exempt\_principals). | `bool` | `null` | no |
| <a name="input_enable_audit_bucket_lock"></a> [enable\_audit\_bucket\_lock](#input\_enable\_audit\_bucket\_lock) | Opt-in WORM lock on the org audit-log GCS bucket (locked retention of audit\_log\_retention\_days). Null (default) = gcp.enable\_audit\_bucket\_lock from config, else false (operator-correctable). A locked policy is IRREVERSIBLE — enable only for compliance regimes that require tamper-proof retention. See docs/known-gaps.md. | `bool` | `null` | no |
| <a name="input_enable_cis_log_metrics"></a> [enable\_cis\_log\_metrics](#input\_enable\_cis\_log\_metrics) | CIS GCP 2.4-2.11 log-based metrics and alerts in the alerting project, fed org-wide by the aggregated org sink (requires enable\_control\_plane\_alerting). Default true. | `bool` | `true` | no |
| <a name="input_enable_cmek_org_policy"></a> [enable\_cmek\_org\_policy](#input\_enable\_cmek\_org\_policy) | Enforce CMEK on sensitive services org-wide (gcp.restrictNonCmekServices). Default false; set true (or use examples/presets/prod-gcp-organization.tfvars) once CMEK keys are wired for cmek\_required\_services. | `bool` | `false` | no |
| <a name="input_enable_control_plane_alerting"></a> [enable\_control\_plane\_alerting](#input\_enable\_control\_plane\_alerting) | Log-match alerts on org IAM / org policy / VPC-SC / sink / custom-role / deny-policy / KMS-destroy changes and on break-glass use. Default true. | `bool` | `true` | no |
| <a name="input_enable_legacy_admin_folder_roles"></a> [enable\_legacy\_admin\_folder\_roles](#input\_enable\_legacy\_admin\_folder\_roles) | Grant the phase-0 bootstrap SA (terraform\_admin\_email) folderAdmin/projectCreator/billing.projectManager/networkAdmin on every folder. Legacy single-identity model; default false because the per-stage plan/apply service accounts replace it. Enable only while migrating an existing deployment. | `bool` | `false` | no |
| <a name="input_enable_log_analytics"></a> [enable\_log\_analytics](#input\_enable\_log\_analytics) | Org audit logs into a Log Analytics-enabled log bucket with a linked BigQuery dataset. Default true. | `bool` | `true` | no |
| <a name="input_enable_logging_organization_settings"></a> [enable\_logging\_organization\_settings](#input\_enable\_logging\_organization\_settings) | Manage org Cloud Logging settings (default log-bucket location = default\_region, optional CMEK). Default false. | `bool` | `false` | no |
| <a name="input_enable_pam"></a> [enable\_pam](#input\_enable\_pam) | Create a just-in-time Privileged Access Manager entitlement for Organization Admin (pam\_eligible\_groups request, pam\_approver\_groups approve). Requires gcp-bootstrap enable\_pam = true. Default false. | `bool` | `false` | no |
| <a name="input_enable_principal_access_boundary"></a> [enable\_principal\_access\_boundary](#input\_enable\_principal\_access\_boundary) | Principal access boundary on every SA in the admin project (this org's resources only). Needs gcp-bootstrap enable\_principal\_access\_boundary. Null (default) = gcp.principal\_access\_boundary from config/landing-zone.yaml (shared with gcp-bootstrap and gcp-guardrails), else false. | `bool` | `null` | no |
| <a name="input_enable_scoped_access_policies"></a> [enable\_scoped\_access\_policies](#input\_enable\_scoped\_access\_policies) | Create one folder-scoped VPC-SC access policy per environment and grant that environment's workload SAs rights on it only (gcp-workload builds its perimeter there). Requires gcp-bootstrap enable\_scoped\_access\_policies = true. Default true. | `bool` | `true` | no |
| <a name="input_enforce_os_login"></a> [enforce\_os\_login](#input\_enforce\_os\_login) | Enforce compute.requireOsLogin at the organization node (CIS GCP 4.4). Default true. | `bool` | `true` | no |
| <a name="input_environments"></a> [environments](#input\_environments) | Map of application environment definitions. is\_production (default false) marks production environments: it drives the production guardrail checks here and in gcp-bootstrap / gcp-workload. Null = gcp.environments from config/landing-zone.yaml (the single source shared by every GCP root and tfc-admin). | <pre>map(object({<br/>    display_name            = string<br/>    region                  = string<br/>    cidr_block              = string<br/>    budget_monthly_limit    = number<br/>    iam_group_role_bindings = map(set(string))<br/>    labels                  = optional(map(string), {})<br/>    is_production           = optional(bool, false)<br/>  }))</pre> | `null` | no |
| <a name="input_guardrail_owner_mode"></a> [guardrail\_owner\_mode](#input\_guardrail\_owner\_mode) | Who applies the org IAM deny policies: "separate" (the gcp-guardrails root, as the gcp-bootstrap guardrails SA; this root only creates and binds the containment tag) or "organization" (this root; legacy). Null = the gcp-bootstrap guardrail\_owner\_mode output ("organization" for an older bootstrap state without it). Must match gcp-bootstrap: in separate mode this root's apply SA has no roles/iam.denyAdmin. | `string` | `null` | no |
| <a name="input_iam_deny_policies"></a> [iam\_deny\_policies](#input\_iam\_deny\_policies) | Opt-in IAM deny policies applied at the org node — a coarse, allow-independent backstop blocking specific permissions for specific principals regardless of roles (deny before allow). Used only in the legacy guardrail\_owner\_mode = "organization"; in separate mode set them on the gcp-guardrails root instead. Default [] = none. See docs/known-gaps.md. | <pre>list(object({<br/>    name         = string<br/>    display_name = optional(string)<br/>    rules = list(object({<br/>      description           = optional(string)<br/>      denied_principals     = list(string)<br/>      denied_permissions    = list(string)<br/>      exception_principals  = optional(list(string), [])<br/>      exception_permissions = optional(list(string), [])<br/>      denial_condition = optional(object({<br/>        expression  = string<br/>        title       = optional(string)<br/>        description = optional(string)<br/>      }))<br/>    }))<br/>  }))</pre> | `[]` | no |
| <a name="input_landing_zone_config_path"></a> [landing\_zone\_config\_path](#input\_landing\_zone\_config\_path) | Path to the single-source landing-zone config (YAML; schema config/landing-zone.example.yaml), absolute or relative to this root. Null = ../../../config/landing-zone.yaml; "" disables the lookup. Read only if the file exists; explicit variables win over its values. | `string` | `null` | no |
| <a name="input_log_analytics_retention_days"></a> [log\_analytics\_retention\_days](#input\_log\_analytics\_retention\_days) | Retention (days, 365-3650) of the audit Log Analytics bucket. | `number` | `400` | no |
| <a name="input_logging_project_id"></a> [logging\_project\_id](#input\_logging\_project\_id) | Dedicated logging project for the org audit sink/bucket, audit CMEK keyring and control-plane alerts (separation of duties). Default null = admin project. MUST NOT be owned by the Terraform admin/automation SA (create it out-of-band or from a separate identity). Decide before the first apply. Requires logging\_project\_number. PREVIEW: not yet validated against a real apply. | `string` | `null` | no |
| <a name="input_logging_project_number"></a> [logging\_project\_number](#input\_logging\_project\_number) | Project number of logging\_project\_id (required when it is set); used for the audit CMEK service-agent grants. | `string` | `null` | no |
| <a name="input_logging_settings_kms_key_name"></a> [logging\_settings\_kms\_key\_name](#input\_logging\_settings\_kms\_key\_name) | Optional CMEK for new projects' \_Default/\_Required log buckets (grant the org Logging SA on it first). Null = Google-managed. | `string` | `null` | no |
| <a name="input_monthly_budget_amount"></a> [monthly\_budget\_amount](#input\_monthly\_budget\_amount) | Monthly budget limit for the organization. Set to 0 to disable budget alerts. | `number` | `1000` | no |
| <a name="input_org_policy_overrides"></a> [org\_policy\_overrides](#input\_org\_policy\_overrides) | Per-constraint overrides of the organization-policy baseline (stage org\_policy\_overrides): set enforce, replace list values, disabled = true to drop, or add a constraint. Use it instead of forking the stage. | <pre>map(object({<br/>    enforce        = optional(bool)<br/>    allowed_values = optional(list(string))<br/>    denied_values  = optional(list(string))<br/>    allow_all      = optional(bool)<br/>    deny_all       = optional(bool)<br/>    disabled       = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_organization_admin_groups"></a> [organization\_admin\_groups](#input\_organization\_admin\_groups) | Bare group emails granted Organization Admin. Standing admin is group-only: at least one is required unless allow\_user\_principals\_for\_break\_glass = true. Null = gcp.organization\_admin\_groups from config/landing-zone.yaml, else []. | `list(string)` | `null` | no |
| <a name="input_organization_name"></a> [organization\_name](#input\_organization\_name) | Name of the organization. Null = org.display\_name from config/landing-zone.yaml, else "My Organization". | `string` | `null` | no |
| <a name="input_os_login_exempt_environment_keys"></a> [os\_login\_exempt\_environment\_keys](#input\_os\_login\_exempt\_environment\_keys) | Environment folder keys exempted from the org-wide OS Login requirement (folder-level override). Strict folders cannot be exempted. Default []. | `list(string)` | `[]` | no |
| <a name="input_pam_approver_groups"></a> [pam\_approver\_groups](#input\_pam\_approver\_groups) | Bare group emails whose members approve just-in-time Organization Admin requests (enable\_pam). Must not overlap pam\_eligible\_groups. | `list(string)` | `[]` | no |
| <a name="input_pam_eligible_groups"></a> [pam\_eligible\_groups](#input\_pam\_eligible\_groups) | Bare group emails whose members may request just-in-time Organization Admin (enable\_pam). | `list(string)` | `[]` | no |
| <a name="input_pam_max_request_duration"></a> [pam\_max\_request\_duration](#input\_pam\_max\_request\_duration) | Maximum just-in-time grant duration, '<seconds>s' (max 86400s). Default 3600s. | `string` | `"3600s"` | no |
| <a name="input_pin_wif_to_tfc_organization"></a> [pin\_wif\_to\_tfc\_organization](#input\_pin\_wif\_to\_tfc\_organization) | Enforce (custom org-policy constraint) that every HCP Terraform workload identity provider references tfc\_organization in its attribute\_condition, so no pipeline can trust another TFC organization. Default true. | `bool` | `true` | no |
| <a name="input_prefer_managed_constraints"></a> [prefer\_managed\_constraints](#input\_prefer\_managed\_constraints) | Use the managed (constraints/*.managed.*) successor of each baseline org-policy constraint where Google offers one. Default true. | `bool` | `true` | no |
| <a name="input_principal_access_boundary_allowed_resources"></a> [principal\_access\_boundary\_allowed\_resources](#input\_principal\_access\_boundary\_allowed\_resources) | Extra/explicit resources the bounded automation SAs may act on. Empty = this organization only. | `list(string)` | `[]` | no |
| <a name="input_project_prefix"></a> [project\_prefix](#input\_project\_prefix) | Short prefix prepended to all GCP project IDs to ensure global uniqueness.<br/>Must start with a lowercase letter; only lowercase letters, digits, and hyphens allowed.<br/>Keep this to 6 characters or fewer — GCP project IDs are capped at 30 characters and<br/>the prefix consumes part of that budget. Null = org.prefix from<br/>config/landing-zone.yaml (shared by every GCP root). The placeholder "my-org" is rejected. | `string` | `null` | no |
| <a name="input_restrict_cloud_run_ingress"></a> [restrict\_cloud\_run\_ingress](#input\_restrict\_cloud\_run\_ingress) | Enforce run.allowedIngress org-wide so Cloud Run services accept only internal or Cloud Load Balancing traffic (never ingress "all"). Public apps are served through the external ALB + Cloud Armor. Default true. | `bool` | `true` | no |
| <a name="input_security_contact_email"></a> [security\_contact\_email](#input\_security\_contact\_email) | Email for security notifications via Essential Contacts (optional) | `string` | `null` | no |
| <a name="input_shared_iam_group_role_bindings"></a> [shared\_iam\_group\_role\_bindings](#input\_shared\_iam\_group\_role\_bindings) | Folder IAM bindings for the shared services folder, keyed by Google Group email | `map(set(string))` | `{}` | no |
| <a name="input_strict_folder_policy_environment_keys"></a> [strict\_folder\_policy\_environment\_keys](#input\_strict\_folder\_policy\_environment\_keys) | Environment folder keys that should receive the stricter folder policy bundle | `list(string)` | <pre>[<br/>  "prod"<br/>]</pre> | no |
| <a name="input_terraform_admin_email"></a> [terraform\_admin\_email](#input\_terraform\_admin\_email) | Service account email for the Terraform admin SA created by the bootstrap stage.<br/>The organization providers impersonate this SA for all API calls, ensuring that<br/>even local runs operate with the SA's permissions rather than the caller's personal<br/>credentials.<br/>Format: terraform-admin@<admin-project-id>.iam.gserviceaccount.com<br/>Set to null only during the very first bootstrap apply when the SA does not exist yet. | `string` | `null` | no |
| <a name="input_tfc_hostname"></a> [tfc\_hostname](#input\_tfc\_hostname) | HCP Terraform / Terraform Enterprise hostname whose dynamic-credential tokens the WIF pools trust (app.terraform.io, app.eu.terraform.io or your TFE host). | `string` | `"app.terraform.io"` | no |
| <a name="input_tfc_organization"></a> [tfc\_organization](#input\_tfc\_organization) | Terraform Cloud organization used for dynamic credentials. Null = org.tfc.organization from config/landing-zone.yaml. | `string` | `null` | no |
| <a name="input_wif_github_owner_ids"></a> [wif\_github\_owner\_ids](#input\_wif\_github\_owner\_ids) | Numeric GitHub owner IDs a GitHub Actions workload identity provider may pin: its attribute\_condition must be exactly assertion.repository\_owner\_id == "<id>" for one of them. Empty (default) leaves GitHub providers tenant-unpinned (the issuer is still allow-listed). | `list(string)` | `[]` | no |
| <a name="input_wif_tenant_pin_enforcement"></a> [wif\_tenant\_pin\_enforcement](#input\_wif\_tenant\_pin\_enforcement) | custom.wifProviderTenantPinned: enforce (default), dry\_run (log only: stage it first on an org with existing WIF providers) or off. | `string` | `"enforce"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_admin_containment_enabled"></a> [admin\_containment\_enabled](#output\_admin\_containment\_enabled) | Whether the admin-containment deny policy is on (explicit enable\_admin\_containment, else gcp.admin\_containment, else on when any environment is\_production). |
| <a name="output_admin_project"></a> [admin\_project](#output\_admin\_project) | Details of the admin project |
| <a name="output_admin_project_number"></a> [admin\_project\_number](#output\_admin\_project\_number) | Admin project number for Workload Identity pool references |
| <a name="output_audit_logs_bucket_name"></a> [audit\_logs\_bucket\_name](#output\_audit\_logs\_bucket\_name) | Cloud Storage bucket receiving organization-wide audit logs |
| <a name="output_audit_project_id"></a> [audit\_project\_id](#output\_audit\_project\_id) | Project holding the org audit bucket, audit CMEK and control-plane alerts (logging\_project\_id, or the admin project). |
| <a name="output_billing_account"></a> [billing\_account](#output\_billing\_account) | Billing account ID for downstream usage |
| <a name="output_billing_export_dataset_id"></a> [billing\_export\_dataset\_id](#output\_billing\_export\_dataset\_id) | BigQuery dataset ID for Cloud Billing export |
| <a name="output_cmek_key_names"></a> [cmek\_key\_names](#output\_cmek\_key\_names) | Map of CMEK key short-name to key ID created by the organization stage. Lets downstream roots (e.g. gcp/workload) encrypt resources with org-managed keys via remote state. Re-exports modules/gcp/stages/organization output cmek\_key\_names. |
| <a name="output_control_plane_alert_policy_ids"></a> [control\_plane\_alert\_policy\_ids](#output\_control\_plane\_alert\_policy\_ids) | Map of control-plane watch name to alert policy ID. |
| <a name="output_default_region"></a> [default\_region](#output\_default\_region) | Default region for resources |
| <a name="output_delegated_folder_iam_targets"></a> [delegated\_folder\_iam\_targets](#output\_delegated\_folder\_iam\_targets) | Folders on which the gcp-projects apply SA holds the conditional folderIamAdmin, with each folder's role allow-list. |
| <a name="output_folders"></a> [folders](#output\_folders) | Map of created folders |
| <a name="output_github_oidc_pool_id"></a> [github\_oidc\_pool\_id](#output\_github\_oidc\_pool\_id) | Workload Identity Pool ID for GitHub Actions OIDC |
| <a name="output_github_oidc_provider_name"></a> [github\_oidc\_provider\_name](#output\_github\_oidc\_provider\_name) | Fully-qualified WIF provider name for use in GitHub Actions (google-github-actions/auth) |
| <a name="output_guardrail_deny_policy_specs"></a> [guardrail\_deny\_policy\_specs](#output\_guardrail\_deny\_policy\_specs) | DEPRECATED (removed in v1.0). gcloud policy-file JSON of the deny policies this root applies in the legacy organization mode; empty in separate mode, where gcp-guardrails owns them (its deny\_policy\_specs output serves the break-glass path). |
| <a name="output_guardrail_owner_mode"></a> [guardrail\_owner\_mode](#output\_guardrail\_owner\_mode) | Deny-policy ownership: "separate" (authored and applied by the gcp-guardrails root) or "organization" (legacy: applied by this root). |
| <a name="output_log_analytics_bucket_id"></a> [log\_analytics\_bucket\_id](#output\_log\_analytics\_bucket\_id) | Audit Log Analytics bucket (null when disabled). |
| <a name="output_org_id"></a> [org\_id](#output\_org\_id) | Organization ID for downstream resource configuration |
| <a name="output_organization"></a> [organization](#output\_organization) | Organization details |
| <a name="output_organization_name"></a> [organization\_name](#output\_organization\_name) | Name of the organization |
| <a name="output_pam_entitlement_name"></a> [pam\_entitlement\_name](#output\_pam\_entitlement\_name) | Resource name of the just-in-time org-admin PAM entitlement (null when enable\_pam = false). |
| <a name="output_principal_access_boundary_policy"></a> [principal\_access\_boundary\_policy](#output\_principal\_access\_boundary\_policy) | Automation principal access boundary policy name (null when disabled). |
| <a name="output_project_prefix"></a> [project\_prefix](#output\_project\_prefix) | Project prefix used for naming |
| <a name="output_scc_pubsub_topic_id"></a> [scc\_pubsub\_topic\_id](#output\_scc\_pubsub\_topic\_id) | Pub/Sub topic receiving Security Command Center findings |
| <a name="output_scoped_access_policy_ids"></a> [scoped\_access\_policy\_ids](#output\_scoped\_access\_policy\_ids) | Map of environment key -> numeric ID of its folder-scoped Access Context Manager policy. |
| <a name="output_tag_keys"></a> [tag\_keys](#output\_tag\_keys) | Map of tag key short names to their Resource Manager resource IDs |
| <a name="output_tag_values"></a> [tag\_values](#output\_tag\_values) | Map of available Resource Manager Tag Values |
| <a name="output_terraform_service_account_email"></a> [terraform\_service\_account\_email](#output\_terraform\_service\_account\_email) | Email of the Terraform Admin Service Account |
| <a name="output_tfc_oidc_pool_id"></a> [tfc\_oidc\_pool\_id](#output\_tfc\_oidc\_pool\_id) | Workload Identity Pool ID for Terraform Cloud OIDC (null if TFC OIDC not configured) |
| <a name="output_tfc_oidc_provider_name"></a> [tfc\_oidc\_provider\_name](#output\_tfc\_oidc\_provider\_name) | Fully-qualified WIF provider name for Terraform Cloud OIDC (null if TFC OIDC not configured) |
<!-- END_TF_DOCS -->
