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
  source = "../../modules/stages/aws-security"

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
	aggregator_role_arn = 
	config_role_arn = 
	forensics_account_id = 
	key_admin_arn = 
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
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |



## Modules


- access_analyzer - ../../aws/access-analyzer-org
- cloudtrail - ../../aws/cloudtrail-org
- config - ../../aws/config-org
- delegated_admin - ../../aws/security-delegated-admin
- firewall_manager - ../../aws/firewall-manager-org
- forensics_cmk - ../../aws/kms-key
- guardduty - ../../aws/guardduty-org
- incident_response - ../../aws/incident-response
- log_archive_bucket - ../../aws/log-archive-bucket
- log_cmk - ../../aws/kms-key
- org_security_service - ../../aws/org-security-service
- sectool_cmk - ../../aws/kms-key
- security_notifications - ../../aws/security-notifications
- securityhub - ../../aws/securityhub-org
- securitylake - ../../aws/securitylake
- service_quotas - ../../aws/service-quotas
- systems_manager - ../../aws/systems-manager




## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aggregator_role_arn"></a> [aggregator\_role\_arn](#input\_aggregator\_role\_arn) | ARN of the IAM role the Config organization aggregator assumes to collect Config data across the organization. | `string` | n/a | yes |
| <a name="input_config_role_arn"></a> [config\_role\_arn](#input\_config\_role\_arn) | ARN of the IAM role AWS Config assumes to record resource configurations in each account/Region. | `string` | n/a | yes |
| <a name="input_forensics_account_id"></a> [forensics\_account\_id](#input\_forensics\_account\_id) | 12-digit account ID of the forensics account trusted to assume the incident-response snapshot-sharing role. Also owns the forensics CMK (targeted via the aws.forensics aliased provider). | `string` | n/a | yes |
| <a name="input_key_admin_arn"></a> [key\_admin\_arn](#input\_key\_admin\_arn) | Account-qualified ARN of the principal granted key administration (kms:*) on both the log and forensics CMKs. REQUIRED to avoid locking the keys out of management. | `string` | n/a | yes |
| <a name="input_log_archive_account_id"></a> [log\_archive\_account\_id](#input\_log\_archive\_account\_id) | 12-digit account ID of the Log-Archive account that owns the central log-archive bucket and the log CMK. Provided for completeness; the account is targeted via the aws.log\_archive aliased provider rather than by ID. | `string` | n/a | yes |
| <a name="input_log_archive_bucket_name"></a> [log\_archive\_bucket\_name](#input\_log\_archive\_bucket\_name) | Deterministic name of the central log-archive bucket. Cross-root naming contract: it must match the name the log-tamper SCP references. | `string` | n/a | yes |
| <a name="input_management_account_id"></a> [management\_account\_id](#input\_management\_account\_id) | 12-digit account ID of the organization management (payer) account. Scopes the CloudTrail EncryptionContext condition on the log CMK. | `string` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | AWS Organizations organization ID (o-xxxxxxxxxx). Scopes the CMK log-service grants and the incident-response forensics-role trust policy to this org. | `string` | n/a | yes |
| <a name="input_org_root_id"></a> [org\_root\_id](#input\_org\_root\_id) | The organization root ID (r-xxxx) the Security Hub baseline configuration policy is associated with. | `string` | n/a | yes |
| <a name="input_security_tooling_account_id"></a> [security\_tooling\_account\_id](#input\_security\_tooling\_account\_id) | 12-digit account ID of the Security Tooling (delegated-administrator) account. GuardDuty, Security Hub, Access Analyzer, Config, and the org-security services are administered from here. | `string` | n/a | yes |
| <a name="input_shared_services_account_id"></a> [shared\_services\_account\_id](#input\_shared\_services\_account\_id) | 12-digit account ID of the Shared-Services (Identity) account nominated as the IAM Identity Center delegated administrator by the security-delegated-admin module. | `string` | n/a | yes |
| <a name="input_aws_enabled_regions"></a> [aws\_enabled\_regions](#input\_aws\_enabled\_regions) | Regions in which the regional security services (Config, GuardDuty, Security Lake) are enabled. One set of per-Region resources is created for each entry. | `list(string)` | <pre>[<br/>  "eu-west-2"<br/>]</pre> | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | Home (aggregation) Region. Used as the Security Hub home\_region for the region-scoped standard ARNs. | `string` | `"eu-west-2"` | no |
| <a name="input_break_glass_role_arn"></a> [break\_glass\_role\_arn](#input\_break\_glass\_role\_arn) | ARN of the break-glass IAM role the security-notifications control watches for assumption. Any AssumeRole against this ARN raises a notification. | `string` | `""` | no |
| <a name="input_cloudtrail_log_group_name"></a> [cloudtrail\_log\_group\_name](#input\_cloudtrail\_log\_group\_name) | Name of the CloudWatch Logs group the organization CloudTrail delivers into, in the security-tooling account. When set (with break\_glass\_role\_arn), the security-notifications control adds a metric-filter + CloudWatch metric ALARM on break-glass AssumeRole. Empty (default) leaves only the always-on EventBridge rule. | `string` | `""` | no |
| <a name="input_enable_firewall_manager"></a> [enable\_firewall\_manager](#input\_enable\_firewall\_manager) | Master switch for AWS Firewall Manager composition. Default false: registering the FMS administrator is an explicit, one-time decision, and the firewall-manager-org module ships a placeholder security-group policy that must be overridden before enabling. When true, the Security Tooling account is registered as FMS admin from the management account. | `bool` | `false` | no |
| <a name="input_enable_incident_response"></a> [enable\_incident\_response](#input\_enable\_incident\_response) | Master switch for the incident-response automation (isolation Lambda, GuardDuty EventBridge rule, forensics snapshot-sharing role). | `bool` | `true` | no |
| <a name="input_enable_security_lake"></a> [enable\_security\_lake](#input\_enable\_security\_lake) | Master COST toggle for Amazon Security Lake. Security Lake incurs ingestion, storage, and normalization charges. | `bool` | `true` | no |
| <a name="input_enable_service_quotas"></a> [enable\_service\_quotas](#input\_enable\_service\_quotas) | Master switch for service-quota management (opt-in). When false, no quota requests or usage alarms are created. | `bool` | `false` | no |
| <a name="input_enabled_security_services"></a> [enabled\_security\_services](#input\_enabled\_security\_services) | Set of org-security services (org-security-service module) to enable: any of macie, inspector, detective, resource-explorer. Detective defaults OFF per SRA. | `set(string)` | <pre>[<br/>  "macie",<br/>  "inspector"<br/>]</pre> | no |
| <a name="input_meta_store_manager_role_arn"></a> [meta\_store\_manager\_role\_arn](#input\_meta\_store\_manager\_role\_arn) | ARN of the AmazonSecurityLakeMetaStoreManager IAM role Security Lake uses to manage the Lake Formation metastore. Required when enable\_security\_lake is true. | `string` | `""` | no |
| <a name="input_notification_subscribers"></a> [notification\_subscribers](#input\_notification\_subscribers) | Subscribers attached to the security-notifications SNS topic, keyed by an arbitrary name. At least one is required (findings would otherwise fire into a void). Defaults to a placeholder SecOps email the root is expected to override. | <pre>map(object({<br/>    protocol = string # "email" | "https" | "sms" | "sqs" | "lambda" | ...<br/>    endpoint = string # e.g. an email address or HTTPS URL<br/>  }))</pre> | <pre>{<br/>  "secops": {<br/>    "endpoint": "secops@example.com",<br/>    "protocol": "email"<br/>  }<br/>}</pre> | no |
| <a name="input_quarantine_vpc_id"></a> [quarantine\_vpc\_id](#input\_quarantine\_vpc\_id) | VPC ID in which the incident-response deny-all quarantine security group is created. Empty (default) skips the SG. Supply the VPC holding the workloads the isolation Lambda may need to quarantine. | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_forensics_account_id"></a> [forensics\_account\_id](#output\_forensics\_account\_id) | 12-digit account ID of the forensics account (echo of the input, part of the cross-root contract). |
| <a name="output_forensics_cmk_arn"></a> [forensics\_cmk\_arn](#output\_forensics\_cmk\_arn) | ARN of the forensics customer-managed KMS key. |
| <a name="output_guardduty_detector_ids"></a> [guardduty\_detector\_ids](#output\_guardduty\_detector\_ids) | Map of Region to the GuardDuty detector ID created in that Region. |
| <a name="output_log_archive_bucket_arn"></a> [log\_archive\_bucket\_arn](#output\_log\_archive\_bucket\_arn) | ARN of the central log-archive bucket. |
| <a name="output_log_archive_bucket_name"></a> [log\_archive\_bucket\_name](#output\_log\_archive\_bucket\_name) | Deterministic name of the central log-archive bucket (the cross-root naming contract). |
| <a name="output_log_cmk_arn"></a> [log\_cmk\_arn](#output\_log\_cmk\_arn) | ARN of the log-archive customer-managed KMS key. |
| <a name="output_sectool_cmk_arn"></a> [sectool\_cmk\_arn](#output\_sectool\_cmk\_arn) | ARN of the security-tooling customer-managed KMS key that encrypts the SNS topic and SSM session data (created in the security-tooling account so those local services can use it). |
| <a name="output_security_notifications_topic_arn"></a> [security\_notifications\_topic\_arn](#output\_security\_notifications\_topic\_arn) | ARN of the security-notifications SNS topic (consumed by downstream usage/alarm actions). |
| <a name="output_securityhub_configuration_policy_id"></a> [securityhub\_configuration\_policy\_id](#output\_securityhub\_configuration\_policy\_id) | UUID of the baseline Security Hub configuration policy. |
<!-- END_TF_DOCS -->
