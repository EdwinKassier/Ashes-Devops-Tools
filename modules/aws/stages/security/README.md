# aws-security stage

Phase-2 orchestration wrapper that composes the SRA security baseline across
four accounts. Each child module is wired to the correct account through one of
four aliased providers:

| Alias | Account |
|-------|---------|
| `aws.management` | organization management (payer) account |
| `aws.security_tooling` | delegated-administrator / security tooling account |
| `aws.log_archive` | central log-archive account |
| `aws.forensics` | forensics account |

Composed children:

- **log_cmk / forensics_cmk / sectool_cmk** (`kms-key`) — customer-managed keys.
  The **log CMK** (log-archive account) encrypts the log-archive bucket,
  CloudTrail, Config, and Security Lake. The **forensics CMK** (forensics
  account) is for snapshot forensics. The **sectool CMK** (security-tooling
  account) encrypts the SNS notifications topic and SSM session data — these
  services run *in* the security-tooling account, so they cannot use the
  cross-account log CMK (whose key policy grants only log-delivery service
  principals + the key admin; a local SNS/SSM call would get `KMSAccessDenied`).
  The sectool CMK grants the local SNS/SSM/CloudWatch service principals usage,
  scoped by `aws:SourceOrgID`.
- **log_archive_bucket** (`log-archive-bucket`) — the hardened, Object-Lock
  central log-archive bucket in the log-archive account.
- **cloudtrail** (`cloudtrail-org`) — organization CloudTrail authored from the
  management account, delivering to the log-archive bucket.
- **config** (`config-org`) — Config recorder, delivery channel, and the
  organization aggregator, from the Security Tooling account with
  `recorder_only = false`. **Convention 9:** recorders for the other member
  accounts come from their own layers / the out-of-band StackSet, not this
  stage.
- **guardduty** (`guardduty-org`) — org-wide GuardDuty, delegated to the
  Security Tooling account and registered from the management account.
- **securityhub** (`securityhub-org`) — Security Hub CENTRAL configuration
  (baseline configuration policy) delegated to the Security Tooling account.
- **access_analyzer** (`access-analyzer-org`) — org external- and unused-access
  analyzers.
- **delegated_admin** (`security-delegated-admin`) — delegated-administrator
  registrations performed from the management account.
- **org_security_service** (`org-security-service`) — Macie / Inspector /
  Detective / Resource Explorer (default: Macie + Inspector).
- **securitylake** (`securitylake`) — Amazon Security Lake (cost-gated).
- **systems_manager** (`systems-manager`) — Session Manager, patch baseline, and
  software-inventory baseline.
- **incident_response** (`incident-response`) — isolation Lambda (with the
  EventBridge invoke permission), GuardDuty EventBridge rule, forensics
  snapshot-sharing role (granted `kms:Decrypt`/`CreateGrant` on the forensics
  CMK), and an optional deny-all quarantine SG (gated on `quarantine_vpc_id`).
- **security_notifications** (`security-notifications`) — sectool-CMK-encrypted
  SNS topic, detective EventBridge rules, and (when `cloudtrail_log_group_name`
  is set) the break-glass CloudWatch metric alarm.
- **service_quotas** (`service-quotas`) — opt-in quota-increase requests and
  usage alarms routed to the notifications topic.
- **firewall_manager** (`firewall-manager-org`) — AWS Firewall Manager, **gated
  OFF by default** (`enable_firewall_manager = false`). When enabled, the
  Security Tooling account is registered as the FMS administrator from the
  management account. It is off by default because registering the FMS admin is
  an explicit, one-time decision and the module ships a placeholder
  security-group policy that must be overridden before use; the default plan
  therefore creates no FMS resources.

The stage exports the cross-root security contract consumed by downstream roots:
`log_archive_bucket_arn`, `log_archive_bucket_name`, `log_cmk_arn`,
`forensics_cmk_arn`, `sectool_cmk_arn`, `guardduty_detector_ids`,
`securityhub_configuration_policy_id`, `security_notifications_topic_arn`, and
`forensics_account_id`.

## Usage

```hcl
provider "aws" {
  alias  = "management"
  region = "eu-west-2"
  assume_role { role_arn = "arn:aws:iam::111111111111:role/tfc-run-role" }
}

provider "aws" {
  alias  = "security_tooling"
  region = "eu-west-2"
  assume_role { role_arn = "arn:aws:iam::222222222222:role/tfc-run-role" }
}

provider "aws" {
  alias  = "log_archive"
  region = "eu-west-2"
  assume_role { role_arn = "arn:aws:iam::333333333333:role/tfc-run-role" }
}

provider "aws" {
  alias  = "forensics"
  region = "eu-west-2"
  assume_role { role_arn = "arn:aws:iam::444444444444:role/tfc-run-role" }
}

module "aws_security" {
  source = "../../modules/aws/stages/security"

  providers = {
    aws.management       = aws.management
    aws.security_tooling = aws.security_tooling
    aws.log_archive      = aws.log_archive
    aws.forensics        = aws.forensics
  }

  org_id                      = "o-abc1234567"
  org_root_id                 = "r-abc1"
  management_account_id       = "111111111111"
  security_tooling_account_id = "222222222222"
  log_archive_account_id      = "333333333333"
  shared_services_account_id  = "555555555555"
  forensics_account_id        = "444444444444"

  log_archive_bucket_name     = "ashes-org-log-archive"
  key_admin_arn               = "arn:aws:iam::333333333333:role/kms-admin"
  config_role_arn             = "arn:aws:iam::222222222222:role/aws-config-role"
  aggregator_role_arn         = "arn:aws:iam::222222222222:role/aws-config-aggregator"
  meta_store_manager_role_arn = "arn:aws:iam::222222222222:role/AmazonSecurityLakeMetaStoreManager"

  notification_subscribers = {
    secops = { protocol = "email", endpoint = "secops@example.com" }
  }
}
```

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	forensics_account_id =
	log_archive_account_id =
	log_archive_bucket_name =
	management_account_id =
	org_id =
	org_root_id =
	security_tooling_account_id =
	shared_services_account_id =
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws.security_tooling"></a> [aws.security\_tooling](#provider\_aws.security\_tooling) | 6.54.0 |

## Modules


- access_analyzer - ../../security/access-analyzer-org
- break_glass - ../../iam/iam-role
- cloudtrail - ../../security/cloudtrail-org
- config - ../../security/config-org
- delegated_admin - ../../security/security-delegated-admin
- firewall_manager - ../../security/firewall-manager-org
- forensics_cmk - ../../data/kms-key
- guardduty - ../../security/guardduty-org
- incident_response - ../../security/incident-response
- log_archive_bucket - ../../data/log-archive-bucket
- log_cmk - ../../data/kms-key
- org_security_service - ../../security/org-security-service
- sectool_cmk - ../../data/kms-key
- security_notifications - ../../security/security-notifications
- securityhub - ../../security/securityhub-org
- securitylake - ../../security/securitylake
- service_quotas - ../../governance/service-quotas
- systems_manager - ../../ops/systems-manager


## Resources

The following resources are created:


- resource.aws_iam_role.securitylake_meta_store (modules/aws/stages/security/securitylake_role.tf#L16)
- resource.aws_iam_role_policy_attachment.securitylake_meta_store (modules/aws/stages/security/securitylake_role.tf#L35)
- data source.aws_caller_identity.security_tooling (modules/aws/stages/security/main.tf#L28)
- data source.aws_partition.security_tooling (modules/aws/stages/security/main.tf#L33)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_forensics_account_id"></a> [forensics\_account\_id](#input\_forensics\_account\_id) | 12-digit account ID of the forensics account trusted to assume the incident-response snapshot-sharing role. Also owns the forensics CMK (targeted via the aws.forensics aliased provider). | `string` | n/a | yes |
| <a name="input_log_archive_account_id"></a> [log\_archive\_account\_id](#input\_log\_archive\_account\_id) | 12-digit account ID of the Log-Archive account that owns the central log-archive bucket and the log CMK. Provided for completeness; the account is targeted via the aws.log\_archive aliased provider rather than by ID. | `string` | n/a | yes |
| <a name="input_log_archive_bucket_name"></a> [log\_archive\_bucket\_name](#input\_log\_archive\_bucket\_name) | Deterministic name of the central log-archive bucket. Cross-root naming contract: it must match the name the log-tamper SCP references. | `string` | n/a | yes |
| <a name="input_management_account_id"></a> [management\_account\_id](#input\_management\_account\_id) | 12-digit account ID of the organization management (payer) account. Scopes the CloudTrail EncryptionContext condition on the log CMK. | `string` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | AWS Organizations organization ID (o-xxxxxxxxxx). Scopes the CMK log-service grants and the incident-response forensics-role trust policy to this org. | `string` | n/a | yes |
| <a name="input_org_root_id"></a> [org\_root\_id](#input\_org\_root\_id) | The organization root ID (r-xxxx) the Security Hub baseline configuration policy is associated with. | `string` | n/a | yes |
| <a name="input_security_tooling_account_id"></a> [security\_tooling\_account\_id](#input\_security\_tooling\_account\_id) | 12-digit account ID of the Security Tooling (delegated-administrator) account. GuardDuty, Security Hub, Access Analyzer, Config, and the org-security services are administered from here. | `string` | n/a | yes |
| <a name="input_shared_services_account_id"></a> [shared\_services\_account\_id](#input\_shared\_services\_account\_id) | 12-digit account ID of the Shared-Services (Identity) account nominated as the IAM Identity Center delegated administrator by the security-delegated-admin module. | `string` | n/a | yes |
| <a name="input_aggregator_role_arn"></a> [aggregator\_role\_arn](#input\_aggregator\_role\_arn) | ARN of an existing IAM role the Config organization aggregator assumes. Null (default) creates aws-config-org-aggregator in the security-tooling account with the AWSConfigRoleForOrganizations managed policy. | `string` | `null` | no |
| <a name="input_aws_enabled_regions"></a> [aws\_enabled\_regions](#input\_aws\_enabled\_regions) | Regions in which the regional security services (Config, GuardDuty, Security Lake) are enabled. One set of per-Region resources is created for each entry. | `list(string)` | <pre>[<br/>  "eu-west-2"<br/>]</pre> | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | Home (aggregation) Region. Used as the Security Hub home\_region for the region-scoped standard ARNs. | `string` | `"eu-west-2"` | no |
| <a name="input_backup_account_id"></a> [backup\_account\_id](#input\_backup\_account\_id) | Dedicated backup account, registered as the AWS Backup delegated administrator. Null = the security-tooling account. | `string` | `null` | no |
| <a name="input_break_glass_active"></a> [break\_glass\_active](#input\_break\_glass\_active) | Set true ONLY during a declared incident to attach AdministratorAccess to the managed break-glass role. False (default) keeps the deny-all standing policy. Flipping this to true should itself be a reviewed, alarmed change. | `bool` | `false` | no |
| <a name="input_break_glass_mfa_max_age"></a> [break\_glass\_mfa\_max\_age](#input\_break\_glass\_mfa\_max\_age) | Maximum age in seconds of the MFA session allowed to assume the managed break-glass role (used only when create\_break\_glass is true). | `number` | `3600` | no |
| <a name="input_break_glass_role_arn"></a> [break\_glass\_role\_arn](#input\_break\_glass\_role\_arn) | ARN of an EXTERNALLY-managed break-glass role to watch for assumption. Ignored when create\_break\_glass is true (the stage then creates and watches its own role). Any AssumeRole against the effective ARN raises a notification. | `string` | `""` | no |
| <a name="input_break_glass_role_name"></a> [break\_glass\_role\_name](#input\_break\_glass\_role\_name) | Name of the managed break-glass role (used only when create\_break\_glass is true). Its ARN is arn:aws:iam::<management-account>:role/<this name> — set the org SCP exemptions to match. | `string` | `"OrganizationBreakGlass"` | no |
| <a name="input_break_glass_trusted_principals"></a> [break\_glass\_trusted\_principals](#input\_break\_glass\_trusted\_principals) | Account-qualified ARNs permitted to assume the managed break-glass role (used only when create\_break\_glass is true). Keep this to a small set of senior responders. MFA is always required. | `list(string)` | `[]` | no |
| <a name="input_cloudtrail_alarm_sns_topic_arn"></a> [cloudtrail\_alarm\_sns\_topic\_arn](#input\_cloudtrail\_alarm\_sns\_topic\_arn) | Optional existing SNS topic ARN for the CIS alarms. Null (default) = a KMS-encrypted topic is created and subscribed with cloudtrail\_alarm\_subscribers. | `string` | `null` | no |
| <a name="input_cloudtrail_alarm_subscribers"></a> [cloudtrail\_alarm\_subscribers](#input\_cloudtrail\_alarm\_subscribers) | Subscribers of the CIS alarm topic. Null (default) = reuse notification\_subscribers. | <pre>map(object({<br/>    protocol = string<br/>    endpoint = string<br/>  }))</pre> | `null` | no |
| <a name="input_cloudtrail_cis_alarms_excluded"></a> [cloudtrail\_cis\_alarms\_excluded](#input\_cloudtrail\_cis\_alarms\_excluded) | CIS alarm keys to skip (see modules/aws/security/cloudtrail-org cis\_alarms\_excluded), e.g. ["unauthorized-api-calls"] if too noisy org-wide. | `list(string)` | `[]` | no |
| <a name="input_cloudtrail_cloudwatch_role_arn"></a> [cloudtrail\_cloudwatch\_role\_arn](#input\_cloudtrail\_cloudwatch\_role\_arn) | Existing CloudTrail -> CloudWatch Logs delivery role (created by aws-organization, create\_org\_trail\_delivery\_role). Null = the cloudtrail-org module creates it, which needs IAM write in the management account. | `string` | `null` | no |
| <a name="input_cloudtrail_lambda_data_events"></a> [cloudtrail\_lambda\_data\_events](#input\_cloudtrail\_lambda\_data\_events) | Record Lambda Invoke data events on the org trail (default false; per-invocation cost). | `bool` | `false` | no |
| <a name="input_cloudtrail_log_group_name"></a> [cloudtrail\_log\_group\_name](#input\_cloudtrail\_log\_group\_name) | Name of the CloudWatch Logs group the organization CloudTrail delivers into, in the security-tooling account. When set (with break\_glass\_role\_arn), the security-notifications control adds a metric-filter + CloudWatch metric ALARM on break-glass AssumeRole. Empty (default) leaves only the always-on EventBridge rule. | `string` | `""` | no |
| <a name="input_cloudtrail_s3_data_events"></a> [cloudtrail\_s3\_data\_events](#input\_cloudtrail\_s3\_data\_events) | S3 object-level data events on the org trail: none, write (CIS 3.8, default), read (CIS 3.9) or all. COST: billed per event across every org account. | `string` | `"write"` | no |
| <a name="input_cloudtrail_s3_data_events_excluded_bucket_arns"></a> [cloudtrail\_s3\_data\_events\_excluded\_bucket\_arns](#input\_cloudtrail\_s3\_data\_events\_excluded\_bucket\_arns) | Extra S3 bucket ARNs excluded from data events (the log-archive bucket is always excluded). | `list(string)` | `[]` | no |
| <a name="input_cloudwatch_logs_kms_key_arn"></a> [cloudwatch\_logs\_kms\_key\_arn](#input\_cloudwatch\_logs\_kms\_key\_arn) | Optional existing CMK ARN (management account) for the CloudTrail CloudWatch Logs group and CIS alarm topic; its policy must grant logs.<region>.amazonaws.com and cloudwatch.amazonaws.com. Null (default) = a dedicated CMK is created. | `string` | `null` | no |
| <a name="input_cloudwatch_logs_retention_days"></a> [cloudwatch\_logs\_retention\_days](#input\_cloudwatch\_logs\_retention\_days) | Retention (days) for the CloudTrail CloudWatch Logs group when enable\_cloudwatch\_logs = true. | `number` | `365` | no |
| <a name="input_config_record_all_supported"></a> [config\_record\_all\_supported](#input\_config\_record\_all\_supported) | AWS Config records ALL supported resource types (default true — the full-coverage but most expensive Config mode). Set false for cost-sensitive non-prod (FinOps F5). | `bool` | `true` | no |
| <a name="input_config_role_arn"></a> [config\_role\_arn](#input\_config\_role\_arn) | ARN of the IAM role AWS Config assumes to record resource configurations in the security-tooling account. Null (default) uses the AWSServiceRoleForConfig service-linked role (created unless create\_config\_service\_linked\_role = false). | `string` | `null` | no |
| <a name="input_create_break_glass"></a> [create\_break\_glass](#input\_create\_break\_glass) | Create and manage the break-glass role in the management account (opt-in), instead of referencing an external one. When true the role's ARN is wired into the assumption alarm automatically and exported. | `bool` | `false` | no |
| <a name="input_create_config_service_linked_role"></a> [create\_config\_service\_linked\_role](#input\_create\_config\_service\_linked\_role) | With config\_role\_arn = null, create the AWSServiceRoleForConfig service-linked role in the security-tooling account. Set false if Config was ever enabled there (the SLR already exists). | `bool` | `true` | no |
| <a name="input_create_organization_trail"></a> [create\_organization\_trail](#input\_create\_organization\_trail) | Create the organization CloudTrail (management account) with its CloudWatch Logs, CIS alarms and KMS wiring. Set false when another owner already runs the org trail, e.g. AWS Control Tower (docs/runbooks/aws-brownfield-adoption.md); two org trails double the cost and the noise. Default true. | `bool` | `true` | no |
| <a name="input_enable_cloudwatch_logs"></a> [enable\_cloudwatch\_logs](#input\_enable\_cloudwatch\_logs) | Attach a CloudWatch Logs group to the org trail and create the full CIS AWS section-4 metric-filter alarm set (4.1-4.15) with a KMS-encrypted SNS topic, all in the management account. Self-sufficient: a logs-granted CMK is created when cloudwatch\_logs\_kms\_key\_arn is null. Default true; set false for S3-only delivery. | `bool` | `true` | no |
| <a name="input_enable_firewall_manager"></a> [enable\_firewall\_manager](#input\_enable\_firewall\_manager) | Master switch for AWS Firewall Manager composition. Default false: registering the FMS administrator is an explicit, one-time decision, and the firewall-manager-org module ships a placeholder security-group policy that must be overridden before enabling. When true, the Security Tooling account is registered as FMS admin from the management account. | `bool` | `false` | no |
| <a name="input_enable_incident_response"></a> [enable\_incident\_response](#input\_enable\_incident\_response) | Master switch for the incident-response automation (isolation Lambda, GuardDuty EventBridge rule, forensics snapshot-sharing role). | `bool` | `true` | no |
| <a name="input_enable_kms_protection_tag"></a> [enable\_kms\_protection\_tag](#input\_enable\_kms\_protection\_tag) | Tag the log-archive, forensics and security-tooling CMKs protected = "true" so the organization deny-tamper SCP blocks key deletion/disablement and protection-tag removal except via break-glass. Default true. | `bool` | `true` | no |
| <a name="input_enable_security_lake"></a> [enable\_security\_lake](#input\_enable\_security\_lake) | Master COST toggle for Amazon Security Lake. Security Lake incurs ingestion, storage, and normalization charges. | `bool` | `true` | no |
| <a name="input_enable_service_quotas"></a> [enable\_service\_quotas](#input\_enable\_service\_quotas) | Master switch for service-quota management (opt-in). When false, no quota requests or usage alarms are created. | `bool` | `false` | no |
| <a name="input_enabled_security_services"></a> [enabled\_security\_services](#input\_enabled\_security\_services) | Set of org-security services (org-security-service module) to enable: any of macie, inspector, detective, resource-explorer. Detective defaults OFF per SRA. | `set(string)` | <pre>[<br/>  "macie",<br/>  "inspector"<br/>]</pre> | no |
| <a name="input_guardduty_enable_ebs_malware_protection"></a> [guardduty\_enable\_ebs\_malware\_protection](#input\_guardduty\_enable\_ebs\_malware\_protection) | GuardDuty agentless EBS malware scanning (default true; billed per GB scanned). Set false for non-prod where it is not required (FinOps F5). | `bool` | `true` | no |
| <a name="input_identity_account_id"></a> [identity\_account\_id](#input\_identity\_account\_id) | Dedicated identity account for IAM Identity Center delegated administration. Default null = the shared-services account (unchanged). Set to a dedicated identity account to tighten the delegated-admin blast radius. PREVIEW: opt-in (default off), not yet validated against a real apply. | `string` | `null` | no |
| <a name="input_key_admin_arn"></a> [key\_admin\_arn](#input\_key\_admin\_arn) | Account-qualified ARN of the principal granted key ADMINISTRATION (management actions only: no Encrypt/Decrypt/GenerateDataKey/ReEncrypt, no CreateGrant) on the log-archive, forensics and security-tooling CMKs. Null (default) grants each key's OWN account role key\_admin\_role\_name (the TFC OIDC baseline tfc-apply role that applies this stage), e.g. arn:aws:iam::<log-archive id>:role/tfc-apply, so the keys can never be locked out of management. Grant key usage separately via kms\_key\_user\_arns. | `string` | `null` | no |
| <a name="input_key_admin_role_name"></a> [key\_admin\_role\_name](#input\_key\_admin\_role\_name) | With key\_admin\_arn = null, the role name (in each CMK's own account) granted key administration. Default tfc-apply: the role the TFC OIDC baseline creates and this stage applies as, so it must already exist. Set to your own per-account admin role if you run with OrganizationAccountAccessRole instead. | `string` | `"tfc-apply"` | no |
| <a name="input_key_policy_admin_role_name"></a> [key\_policy\_admin\_role\_name](#input\_key\_policy\_admin\_role\_name) | Role name (optionally path-prefixed), in each CMK's OWN account, granted kms:PutKeyPolicy — and nothing else — on the log-archive, forensics and security-tooling CMKs. Default break-glass: the member break-glass role the aws-organization stage deploys to every member account (enable\_member\_break\_glass\_role), so the pipeline key admin cannot rewrite a key policy to grant itself kms:Decrypt. The role must exist before this stage creates the keys (KMS rejects unknown principals), and later key-policy changes must be applied as it. Null = legacy: key admin also holds PutKeyPolicy. | `string` | `"break-glass"` | no |
| <a name="input_kms_key_user_arns"></a> [kms\_key\_user\_arns](#input\_kms\_key\_user\_arns) | Principals granted key USAGE (Encrypt/Decrypt/ReEncrypt/GenerateDataKey/DescribeKey) per CMK, keyed by log\_archive / forensics / security\_tooling. Separate from key\_admin\_arn (administration only). Missing keys mean no general-usage grant beyond the built-in service-principal grants. | `map(list(string))` | `{}` | no |
| <a name="input_meta_store_manager_role_arn"></a> [meta\_store\_manager\_role\_arn](#input\_meta\_store\_manager\_role\_arn) | ARN of an existing AmazonSecurityLakeMetaStoreManager role. Empty (default) with enable\_security\_lake: the stage creates AmazonSecurityLakeMetaStoreManagerV2 in the security-tooling account (with the tfc-apply boundary). | `string` | `""` | no |
| <a name="input_notification_subscribers"></a> [notification\_subscribers](#input\_notification\_subscribers) | Subscribers attached to the security-notifications SNS topic, keyed by an arbitrary name. At least one is required (findings would otherwise fire into a void). Defaults to a placeholder SecOps email the root is expected to override. | <pre>map(object({<br/>    protocol = string # one of: email, https, sms, sqs, lambda, etc.<br/>    endpoint = string # e.g. an email address or HTTPS URL<br/>  }))</pre> | <pre>{<br/>  "secops": {<br/>    "endpoint": "secops@example.com",<br/>    "protocol": "email"<br/>  }<br/>}</pre> | no |
| <a name="input_partition"></a> [partition](#input\_partition) | AWS partition (aws, aws-us-gov, aws-cn) for the ARNs this stage builds when the security-tooling partition is not read. | `string` | `"aws"` | no |
| <a name="input_quarantine_vpc_id"></a> [quarantine\_vpc\_id](#input\_quarantine\_vpc\_id) | VPC ID in which the incident-response deny-all quarantine security group is created. Empty (default) skips the SG. Supply the VPC holding the workloads the isolation Lambda may need to quarantine. | `string` | `""` | no |
| <a name="input_tfc_apply_boundary_policy_name"></a> [tfc\_apply\_boundary\_policy\_name](#input\_tfc\_apply\_boundary\_policy\_name) | Name of the tfc-apply permissions-boundary managed policy (tfc-oidc-baseline apply\_boundary\_policy\_name). Every IAM role this stage creates in the security-tooling account (Config aggregator, incident-response roles; management-account roles are unaffected) gets permissions\_boundary = arn:PARTITION:iam::ACCOUNT\_ID:policy/NAME, derived from that account's provider, which the member-account tfc-apply role requires when boundary propagation is on. Null = create roles without a boundary. | `string` | `"tfc-apply-boundary"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_break_glass_role_arn"></a> [break\_glass\_role\_arn](#output\_break\_glass\_role\_arn) | ARN of the break-glass role the assumption alarm watches: the stage-managed role when create\_break\_glass is true, else the externally-managed ARN passed in. Use it to set the org SCP break-glass exemptions. Empty when neither is set. |
| <a name="output_cis_alarm_sns_topic_arn"></a> [cis\_alarm\_sns\_topic\_arn](#output\_cis\_alarm\_sns\_topic\_arn) | SNS topic (management account) the CIS section-4 alarms publish to; null when enable\_cloudwatch\_logs = false. |
| <a name="output_cloudtrail_log_group_name"></a> [cloudtrail\_log\_group\_name](#output\_cloudtrail\_log\_group\_name) | CloudWatch Logs group the org trail delivers into (management account); null when enable\_cloudwatch\_logs = false. |
| <a name="output_config_aggregator_role_arn"></a> [config\_aggregator\_role\_arn](#output\_config\_aggregator\_role\_arn) | IAM role the Config organization aggregator assumes (created by the stage unless aggregator\_role\_arn was set). |
| <a name="output_config_role_arn"></a> [config\_role\_arn](#output\_config\_role\_arn) | IAM role the security-tooling Config recorders use (the AWSServiceRoleForConfig SLR unless config\_role\_arn was set). |
| <a name="output_forensics_account_id"></a> [forensics\_account\_id](#output\_forensics\_account\_id) | 12-digit account ID of the forensics account (echo of the input, part of the cross-root contract). |
| <a name="output_forensics_cmk_arn"></a> [forensics\_cmk\_arn](#output\_forensics\_cmk\_arn) | ARN of the forensics customer-managed KMS key. |
| <a name="output_guardduty_detector_ids"></a> [guardduty\_detector\_ids](#output\_guardduty\_detector\_ids) | Map of Region to the GuardDuty detector ID created in that Region. |
| <a name="output_key_admin_arns"></a> [key\_admin\_arns](#output\_key\_admin\_arns) | Key administrator per CMK (log\_archive / forensics / security\_tooling): key\_admin\_arn, or each key account's key\_admin\_role\_name role when null. |
| <a name="output_log_archive_bucket_arn"></a> [log\_archive\_bucket\_arn](#output\_log\_archive\_bucket\_arn) | ARN of the central log-archive bucket. |
| <a name="output_log_archive_bucket_name"></a> [log\_archive\_bucket\_name](#output\_log\_archive\_bucket\_name) | Deterministic name of the central log-archive bucket (the cross-root naming contract). |
| <a name="output_log_cmk_arn"></a> [log\_cmk\_arn](#output\_log\_cmk\_arn) | ARN of the log-archive customer-managed KMS key. |
| <a name="output_sectool_cmk_arn"></a> [sectool\_cmk\_arn](#output\_sectool\_cmk\_arn) | ARN of the security-tooling customer-managed KMS key that encrypts the SNS topic and SSM session data (created in the security-tooling account so those local services can use it). |
| <a name="output_security_notifications_topic_arn"></a> [security\_notifications\_topic\_arn](#output\_security\_notifications\_topic\_arn) | ARN of the security-notifications SNS topic (consumed by downstream usage/alarm actions). |
| <a name="output_securityhub_configuration_policy_id"></a> [securityhub\_configuration\_policy\_id](#output\_securityhub\_configuration\_policy\_id) | UUID of the baseline Security Hub configuration policy. |
<!-- END_TF_DOCS -->
