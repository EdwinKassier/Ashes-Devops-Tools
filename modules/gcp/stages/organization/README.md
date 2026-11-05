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

  # Access Configuration
  admin_email = "admin@example.com"
}
```

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
	admin_email =
	admin_project_id =
	admin_project_number =
	allowed_regions =
	billing_account =
	billing_admin_groups =
	budget_currency =
	customer_id =
	default_region =
	domain =
	environments =
	monthly_budget_amount =
	org_id =
	organization_admin_groups =
	project_prefix =
	strict_folder_policy_environment_keys =
	terraform_admin_email =

}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.31.0 |

## Modules


- audit_cmek - ../../governance/kms
- audit_logs - ../../governance/cloud-audit-logs
- cmek - ../../governance/kms
- control_plane_alerting - ../../monitoring/control-plane
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


- resource.google_bigquery_dataset.billing_export (modules/gcp/stages/organization/main.tf#L521)
- resource.google_bigquery_dataset_iam_member.billing_export_writer (modules/gcp/stages/organization/main.tf#L552)
- resource.google_essential_contacts_contact.billing (modules/gcp/stages/organization/main.tf#L493)
- resource.google_essential_contacts_contact.security (modules/gcp/stages/organization/main.tf#L484)
- resource.google_folder_iam_member.terraform_admin_folder_roles (modules/gcp/stages/organization/main.tf#L31)
- resource.google_tags_location_tag_binding.containment_audit_keyring (modules/gcp/stages/organization/containment.tf#L27)
- resource.google_tags_location_tag_binding.containment_buckets (modules/gcp/stages/organization/containment.tf#L19)
- resource.google_tags_tag_binding.environment (modules/gcp/stages/organization/tags_binding.tf#L1)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_admin_email"></a> [admin\_email](#input\_admin\_email) | Email address of the primary administrator | `string` | n/a | yes |
| <a name="input_admin_project_id"></a> [admin\_project\_id](#input\_admin\_project\_id) | The project ID of the bootstrap admin project | `string` | n/a | yes |
| <a name="input_admin_project_number"></a> [admin\_project\_number](#input\_admin\_project\_number) | The numeric project number of the bootstrap admin project (digits only) | `string` | n/a | yes |
| <a name="input_allowed_regions"></a> [allowed\_regions](#input\_allowed\_regions) | List of GCP regions permitted by resource location org policy | `list(string)` | n/a | yes |
| <a name="input_billing_account"></a> [billing\_account](#input\_billing\_account) | The GCP billing account ID in format XXXXXX-XXXXXX-XXXXXX | `string` | n/a | yes |
| <a name="input_billing_admin_groups"></a> [billing\_admin\_groups](#input\_billing\_admin\_groups) | List of Google Group email addresses to grant billing admin roles | `list(string)` | n/a | yes |
| <a name="input_budget_currency"></a> [budget\_currency](#input\_budget\_currency) | ISO 4217 currency code for the budget (e.g., USD, EUR, GBP) | `string` | n/a | yes |
| <a name="input_customer_id"></a> [customer\_id](#input\_customer\_id) | The Google Workspace customer ID (format: 'C' followed by alphanumerics, e.g., 'C0abc1234') | `string` | n/a | yes |
| <a name="input_default_region"></a> [default\_region](#input\_default\_region) | Default GCP region for regional resources (e.g., 'us-central1', 'europe-west1') | `string` | n/a | yes |
| <a name="input_domain"></a> [domain](#input\_domain) | The primary domain of the GCP organization (e.g., 'example.com') | `string` | n/a | yes |
| <a name="input_environments"></a> [environments](#input\_environments) | Map of environment definitions keyed by environment name (e.g., dev, staging, prod) | <pre>map(object({<br/>    display_name            = string<br/>    description             = string<br/>    iam_group_role_bindings = map(set(string))<br/>  }))</pre> | n/a | yes |
| <a name="input_monthly_budget_amount"></a> [monthly\_budget\_amount](#input\_monthly\_budget\_amount) | Monthly budget cap in the configured currency. Set to 0 to disable budget alerts (no Budget resource will be created). Must be >= 0. | `number` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | The numeric GCP organization ID (digits only, no 'organizations/' prefix) | `string` | n/a | yes |
| <a name="input_organization_admin_groups"></a> [organization\_admin\_groups](#input\_organization\_admin\_groups) | List of Google Group email addresses to grant organization admin roles | `list(string)` | n/a | yes |
| <a name="input_project_prefix"></a> [project\_prefix](#input\_project\_prefix) | Short prefix applied to all project IDs to ensure global uniqueness (lowercase letters, digits, hyphens; starts with letter) | `string` | n/a | yes |
| <a name="input_strict_folder_policy_environment_keys"></a> [strict\_folder\_policy\_environment\_keys](#input\_strict\_folder\_policy\_environment\_keys) | Subset of environment keys that enforce strict resource location policies | `list(string)` | n/a | yes |
| <a name="input_terraform_admin_email"></a> [terraform\_admin\_email](#input\_terraform\_admin\_email) | Email address of the Terraform admin service account | `string` | n/a | yes |
| <a name="input_alert_notification_channels"></a> [alert\_notification\_channels](#input\_alert\_notification\_channels) | IDs of existing Cloud Monitoring notification channels (projects/<p>/notificationChannels/<id>) attached to every control-plane alert. Default []. | `list(string)` | `[]` | no |
| <a name="input_alert_notification_emails"></a> [alert\_notification\_emails](#input\_alert\_notification\_emails) | Email addresses notified by the control-plane alerts (one email channel each). Default [] — a check warns if no destination is set. | `list(string)` | `[]` | no |
| <a name="input_audit_log_retention_days"></a> [audit\_log\_retention\_days](#input\_audit\_log\_retention\_days) | Number of days to retain audit logs in Cloud Storage. Adjust to meet your<br/>compliance requirements:<br/>  - Default (365 days) — sufficient for most cloud security baselines.<br/>  - PCI-DSS requires 12 months online + 12 months archival.<br/>  - HIPAA requires 6 years.<br/>  - FedRAMP requires 3 years.<br/>Must be >= 1. | `number` | `365` | no |
| <a name="input_audit_soft_delete_retention_days"></a> [audit\_soft\_delete\_retention\_days](#input\_audit\_soft\_delete\_retention\_days) | Soft-delete window (days) on the org audit-log buckets (M-4): deleted/overwritten objects stay restorable for this long. 7-90, or 0 to disable. Default 30. | `number` | `30` | no |
| <a name="input_billing_contact_email"></a> [billing\_contact\_email](#input\_billing\_contact\_email) | Email address for billing notifications and budget alerts via Essential Contacts. Optional — if null, no Essential Contact is registered for the BILLING category. | `string` | `null` | no |
| <a name="input_break_glass_principal_emails"></a> [break\_glass\_principal\_emails](#input\_break\_glass\_principal\_emails) | Extra break-glass principal emails (users/SAs) whose ANY admin action raises a CRITICAL control-plane alert. break\_glass\_user is always included. Group membership is not visible in audit logs, so list the member accounts of a break-glass group here. | `list(string)` | `[]` | no |
| <a name="input_break_glass_user"></a> [break\_glass\_user](#input\_break\_glass\_user) | Optional email address of a break-glass emergency user granted org admin access | `string` | `null` | no |
| <a name="input_cmek_required_services"></a> [cmek\_required\_services](#input\_cmek\_required\_services) | Services that require CMEK when enable\_cmek\_org\_policy is true. Admins tune this list. | `list(string)` | <pre>[<br/>  "storage.googleapis.com",<br/>  "bigquery.googleapis.com",<br/>  "sqladmin.googleapis.com",<br/>  "spanner.googleapis.com",<br/>  "pubsub.googleapis.com",<br/>  "secretmanager.googleapis.com"<br/>]</pre> | no |
| <a name="input_containment_exempt_principals"></a> [containment\_exempt\_principals](#input\_containment\_exempt\_principals) | Break-glass principals exempt from the C2 containment deny policy, e.g. ["principalSet://goog/group/break-glass@example.com"]. Required (non-empty) when enable\_admin\_containment is true. | `list(string)` | `[]` | no |
| <a name="input_custom_org_constraints"></a> [custom\_org\_constraints](#input\_custom\_org\_constraints) | Opt-in custom organization-policy constraints (CEL-defined resource-shape guardrails) applied at the org node. Default [] = none. Latest Google guidance recommends layering custom constraints on the managed baseline; see docs/known-gaps.md (G6). | <pre>list(object({<br/>    name           = string<br/>    display_name   = string<br/>    description    = string<br/>    action_type    = string<br/>    condition      = string<br/>    method_types   = list(string)<br/>    resource_types = list(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_enable_admin_containment"></a> [enable\_admin\_containment](#input\_enable\_admin\_containment) | C2/C3: IAM deny policy at the org node that blocks, for all principals except containment\_exempt\_principals (break-glass): org-wide update/delete of logging sinks, exclusion changes, log-bucket delete, VPC-SC perimeter update/delete/replaceAll/commit and access-policy delete; and, scoped by the containment/protected tag to the audit buckets + audit CMEK keyring, bucket delete/setIamPolicy, object delete, key-version destroy and key setIamPolicy. Once on, Terraform changes to ANY sink, exclusion or perimeter must run as break-glass. Default false; the prod preset turns it on. | `bool` | `false` | no |
| <a name="input_enable_audit_bucket_lock"></a> [enable\_audit\_bucket\_lock](#input\_enable\_audit\_bucket\_lock) | Opt-in WORM lock on the org audit-log GCS bucket (a locked retention policy of audit\_log\_retention\_days). Default false preserves the current behaviour (versioned + access-controlled but not immutable, and a lifecycle delete that can be corrected). Enable only for compliance regimes that require tamper-proof retention — a locked policy CANNOT be shortened or removed. See docs/known-gaps.md (G8). | `bool` | `false` | no |
| <a name="input_enable_cis_log_metrics"></a> [enable\_cis\_log\_metrics](#input\_enable\_cis\_log\_metrics) | With enable\_control\_plane\_alerting, also create the CIS GCP 2.4-2.11 log-based metrics and alert policies (project ownership, audit config, custom roles, firewall rules, routes, networks, Cloud Storage IAM, Cloud SQL config) in the audit/logging project. The aggregated org sink feeds them every project's Admin Activity logs, so one set covers the org. Default true. | `bool` | `true` | no |
| <a name="input_enable_cmek_org_policy"></a> [enable\_cmek\_org\_policy](#input\_enable\_cmek\_org\_policy) | H1/M2: enforce CMEK on sensitive services org-wide via the gcp.restrictNonCmekServices org policy. Default false, so a default apply is unchanged; the prod-hardening preset turns it on. Enabling denies creating resources in cmek\_required\_services without a customer-managed key, so wire CMEK keys for those services first. | `bool` | `false` | no |
| <a name="input_enable_control_plane_alerting"></a> [enable\_control\_plane\_alerting](#input\_enable\_control\_plane\_alerting) | Create log-match alerts on control-plane changes (org IAM, org policy, VPC-SC, sinks/exclusions, custom roles, deny policies, KMS key destroy) and on break-glass use, in the audit/logging project. Default true. | `bool` | `true` | no |
| <a name="input_enable_legacy_admin_folder_roles"></a> [enable\_legacy\_admin\_folder\_roles](#input\_enable\_legacy\_admin\_folder\_roles) | Grant the phase-0 bootstrap SA (terraform\_admin\_email) folderAdmin/projectCreator/billing.projectManager/networkAdmin on every folder. Legacy single-identity model; default false because the per-stage plan/apply service accounts replace it. Enable only while migrating an existing deployment. | `bool` | `false` | no |
| <a name="input_enforce_os_login"></a> [enforce\_os\_login](#input\_enforce\_os\_login) | Enforce compute.requireOsLogin at the organization node (CIS GCP 4.4), so every VM in every folder must use OS Login. Exempt folders via os\_login\_exempt\_environment\_keys. Default true. | `bool` | `true` | no |
| <a name="input_iam_deny_policies"></a> [iam\_deny\_policies](#input\_iam\_deny\_policies) | Opt-in IAM deny policies applied at the org node — a coarse, allow-independent backstop that blocks specific permissions for specific principals regardless of roles held (deny is evaluated before allow). Default [] = none. See docs/known-gaps.md (G9). | <pre>list(object({<br/>    name         = string<br/>    display_name = optional(string)<br/>    rules = list(object({<br/>      description           = optional(string)<br/>      denied_principals     = list(string)<br/>      denied_permissions    = list(string)<br/>      exception_principals  = optional(list(string), [])<br/>      exception_permissions = optional(list(string), [])<br/>      denial_condition = optional(object({<br/>        expression  = string<br/>        title       = optional(string)<br/>        description = optional(string)<br/>      }))<br/>    }))<br/>  }))</pre> | `[]` | no |
| <a name="input_logging_project_id"></a> [logging\_project\_id](#input\_logging\_project\_id) | Dedicated logging project ID for the org audit sink, audit bucket, BigQuery audit<br/>dataset, audit CMEK keyring and control-plane alerts (separation of duties).<br/>Default null = the admin/bootstrap project (unchanged).<br/>The project MUST NOT be owned (roles/owner, roles/editor, or storage/KMS admin) by the<br/>Terraform admin / automation service account — otherwise the identity being audited<br/>can delete object generations or destroy the key protecting its own audit trail.<br/>Create it out-of-band (or from a separate identity) and grant the automation SA only<br/>what it needs to manage the resources here. Decide BEFORE the first apply: KMS keys<br/>cannot be deleted, so moving the audit keys later orphans the old ones.<br/>Requires logging\_project\_number. PREVIEW: not yet validated against a real apply. | `string` | `null` | no |
| <a name="input_logging_project_number"></a> [logging\_project\_number](#input\_logging\_project\_number) | Numeric project number of logging\_project\_id (required when it is set). Used to grant the logging project's GCS and BigQuery service agents access to the audit CMEK keys. | `string` | `null` | no |
| <a name="input_os_login_exempt_environment_keys"></a> [os\_login\_exempt\_environment\_keys](#input\_os\_login\_exempt\_environment\_keys) | Environment folder keys exempted from the org-wide OS Login requirement (a folder-level compute.requireOsLogin = false override). Keys in strict\_folder\_policy\_environment\_keys cannot be exempted. Default [] = no exemptions. | `list(string)` | `[]` | no |
| <a name="input_security_contact_email"></a> [security\_contact\_email](#input\_security\_contact\_email) | Email address for security notifications via Essential Contacts (SCC alerts, compliance notifications). Optional — if null, no Essential Contact is registered for the SECURITY category. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_admin_containment_rules"></a> [admin\_containment\_rules](#output\_admin\_containment\_rules) | Rules of the C2/C3 admin-containment IAM deny policy (empty when enable\_admin\_containment = false): denied permissions, exempt principals and whether the rule is tag-scoped to the audit store. |
| <a name="output_audit_logs_bucket_name"></a> [audit\_logs\_bucket\_name](#output\_audit\_logs\_bucket\_name) | Name of the Cloud Storage bucket receiving audit logs |
| <a name="output_audit_org_sink_name"></a> [audit\_org\_sink\_name](#output\_audit\_org\_sink\_name) | Name of the org-level audit-log sink that exports to the audit bucket |
| <a name="output_audit_project_id"></a> [audit\_project\_id](#output\_audit\_project\_id) | Project holding the org audit bucket, audit CMEK and control-plane alerts (logging\_project\_id, or the admin project when unset) |
| <a name="output_billing_export_dataset_id"></a> [billing\_export\_dataset\_id](#output\_billing\_export\_dataset\_id) | BigQuery dataset ID for Cloud Billing export data |
| <a name="output_cmek_key_names"></a> [cmek\_key\_names](#output\_cmek\_key\_names) | Map of KMS key short names to fully qualified key resource IDs created by the CMEK modules (org keyring plus, when logging\_project\_id is set, the audit keyring in the logging project) |
| <a name="output_control_plane_alert_policy_ids"></a> [control\_plane\_alert\_policy\_ids](#output\_control\_plane\_alert\_policy\_ids) | Map of control-plane watch name to alert policy ID (empty when enable\_control\_plane\_alerting = false) |
| <a name="output_control_plane_cis_log_metric_names"></a> [control\_plane\_cis\_log\_metric\_names](#output\_control\_plane\_cis\_log\_metric\_names) | Map of CIS GCP 2.4-2.11 log-metric key to log-based metric name in the alerting project (empty when disabled) |
| <a name="output_control_plane_org_log_route_sink_name"></a> [control\_plane\_org\_log\_route\_sink\_name](#output\_control\_plane\_org\_log\_route\_sink\_name) | Aggregated org sink routing Admin Activity logs to the alerting project (null when alerting is off) |
| <a name="output_control_plane_watched_names"></a> [control\_plane\_watched\_names](#output\_control\_plane\_watched\_names) | Names of the active control-plane alert watches |
| <a name="output_folders"></a> [folders](#output\_folders) | Map of created folders |
| <a name="output_iam_deny_policy_names"></a> [iam\_deny\_policy\_names](#output\_iam\_deny\_policy\_names) | Names of the IAM deny policies planned at the org node (containment + iam\_deny\_policies) |
| <a name="output_org_policy_constraints"></a> [org\_policy\_constraints](#output\_org\_policy\_constraints) | Org-node policy constraints this stage manages (boolean + list), for downstream verification |
| <a name="output_organization_id"></a> [organization\_id](#output\_organization\_id) | Organization ID |
| <a name="output_os_login_exempt_environment_keys"></a> [os\_login\_exempt\_environment\_keys](#output\_os\_login\_exempt\_environment\_keys) | Environment folders exempted from the org-wide OS Login requirement (empty when none, or when enforce\_os\_login = false) |
| <a name="output_scc_pubsub_topic_id"></a> [scc\_pubsub\_topic\_id](#output\_scc\_pubsub\_topic\_id) | Pub/Sub topic ID receiving Security Command Center findings notifications |
| <a name="output_strict_folder_policy_environment_keys"></a> [strict\_folder\_policy\_environment\_keys](#output\_strict\_folder\_policy\_environment\_keys) | Environment folders that received the strict folder org-policy bundle |
| <a name="output_tag_keys"></a> [tag\_keys](#output\_tag\_keys) | Tag keys available to downstream consumers |
| <a name="output_tag_value_ids"></a> [tag\_value\_ids](#output\_tag\_value\_ids) | Tag values available to downstream consumers |
<!-- END_TF_DOCS -->
