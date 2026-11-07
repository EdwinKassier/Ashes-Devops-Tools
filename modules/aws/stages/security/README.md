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

  # Every tuning input sits in one object, the aws section. Unset keys take
  # the defaults listed in the aws input below; log_archive_bucket_name is required.
  aws = {
    log_archive_bucket_name     = "ashes-org-log-archive"
    key_admin_arn               = "arn:aws:iam::333333333333:role/kms-admin"
    config_role_arn             = "arn:aws:iam::222222222222:role/aws-config-role"
    aggregator_role_arn         = "arn:aws:iam::222222222222:role/aws-config-aggregator"
    meta_store_manager_role_arn = "arn:aws:iam::222222222222:role/AmazonSecurityLakeMetaStoreManager"

    notification_subscribers = {
      secops = { protocol = "email", endpoint = "secops@example.com" }
    }
  }
}
```

The `envs/aws/security` root builds `aws` from `config/landing-zone.yaml`
(`aws.*`, `notifications.emails`, `org.profile`) with its `aws_overrides`
variable on top: a set override key wins, an unset one keeps the config value,
else the default here.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	forensics_account_id =
	log_archive_account_id =
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
| <a name="provider_aws.security_tooling"></a> [aws.security\_tooling](#provider\_aws.security\_tooling) | 6.72.0 |

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
| <a name="input_management_account_id"></a> [management\_account\_id](#input\_management\_account\_id) | 12-digit account ID of the organization management (payer) account. Scopes the CloudTrail EncryptionContext condition on the log CMK. | `string` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | AWS Organizations organization ID (o-xxxxxxxxxx). Scopes the CMK log-service grants and the incident-response forensics-role trust policy to this org. | `string` | n/a | yes |
| <a name="input_org_root_id"></a> [org\_root\_id](#input\_org\_root\_id) | The organization root ID (r-xxxx) the Security Hub baseline configuration policy is associated with. | `string` | n/a | yes |
| <a name="input_security_tooling_account_id"></a> [security\_tooling\_account\_id](#input\_security\_tooling\_account\_id) | 12-digit account ID of the Security Tooling (delegated-administrator) account. GuardDuty, Security Hub, Access Analyzer, Config, and the org-security services are administered from here. | `string` | n/a | yes |
| <a name="input_shared_services_account_id"></a> [shared\_services\_account\_id](#input\_shared\_services\_account\_id) | 12-digit account ID of the Shared-Services (Identity) account nominated as the IAM Identity Center delegated administrator by the security-delegated-admin module. | `string` | n/a | yes |
| <a name="input_aws"></a> [aws](#input\_aws) | The aws section of the security stage: every tuning input the aws-security root takes from config/landing-zone.yaml (aws.*) or from its aws\_overrides variable, in one object. Each attribute is documented in the type; an unset (or null) attribute takes the default shown there. log\_archive\_bucket\_name is required. The root fills notification\_subscribers, the profile-driven toggles and cloudtrail\_cloudwatch\_role\_arn from its own derivations. | <pre>object({<br/>    # Regions in which the regional security services (Config, GuardDuty, Security Lake) are enabled.<br/>    # One set of per-Region resources is created for each entry.<br/>    aws_enabled_regions = optional(list(string), ["eu-west-2"])<br/>    # Deterministic name of the central log-archive bucket. Cross-root naming contract: it must match<br/>    # the name the log-tamper SCP references.<br/>    log_archive_bucket_name = optional(string)<br/>    # Account-qualified ARN of the principal granted key ADMINISTRATION (management actions only: no<br/>    # Encrypt/Decrypt/GenerateDataKey/ReEncrypt, no CreateGrant) on the log-archive, forensics and<br/>    # security-tooling CMKs. Null (default) grants each key's OWN account role key_admin_role_name<br/>    # (the TFC OIDC baseline tfc-apply role that applies this stage), e.g. arn:aws:iam::<log-archive<br/>    # id>:role/tfc-apply, so the keys can never be locked out of management. Grant key usage<br/>    # separately via kms_key_user_arns.<br/>    key_admin_arn = optional(string)<br/>    # With key_admin_arn = null, the role name (in each CMK's own account) granted key administration.<br/>    # Default tfc-apply: the role the TFC OIDC baseline creates and this stage applies as, so it must<br/>    # already exist. Set to your own per-account admin role if you run with<br/>    # OrganizationAccountAccessRole instead.<br/>    key_admin_role_name = optional(string, "tfc-apply")<br/>    # Principals granted key USAGE (Encrypt/Decrypt/ReEncrypt/GenerateDataKey/DescribeKey) per CMK,<br/>    # keyed by log_archive / forensics / security_tooling. Separate from key_admin_arn (administration<br/>    # only). Missing keys mean no general-usage grant beyond the built-in service-principal grants.<br/>    kms_key_user_arns = optional(map(list(string)), {})<br/>    # Tag the log-archive, forensics and security-tooling CMKs protected = "true" so the organization<br/>    # deny-tamper SCP blocks key deletion/disablement and protection-tag removal except via break-<br/>    # glass. Default true.<br/>    enable_kms_protection_tag = optional(bool, true)<br/>    # ARN of the IAM role AWS Config assumes to record resource configurations in the security-tooling<br/>    # account. Null (default) uses the AWSServiceRoleForConfig service-linked role (created unless<br/>    # create_config_service_linked_role = false).<br/>    config_role_arn = optional(string)<br/>    # With config_role_arn = null, create the AWSServiceRoleForConfig service-linked role in the<br/>    # security-tooling account. Set false if Config was ever enabled there (the SLR already exists).<br/>    create_config_service_linked_role = optional(bool, true)<br/>    # ARN of an existing IAM role the Config organization aggregator assumes. Null (default) creates<br/>    # aws-config-org-aggregator in the security-tooling account with the AWSConfigRoleForOrganizations<br/>    # managed policy.<br/>    aggregator_role_arn = optional(string)<br/>    # ARN of an existing AmazonSecurityLakeMetaStoreManager role. Empty (default) with<br/>    # enable_security_lake: the stage creates AmazonSecurityLakeMetaStoreManagerV2 in the security-<br/>    # tooling account (with the tfc-apply boundary).<br/>    meta_store_manager_role_arn = optional(string, "")<br/>    # ARN of an EXTERNALLY-managed break-glass role to watch for assumption. Ignored when<br/>    # create_break_glass is true (the stage then creates and watches its own role). Any AssumeRole<br/>    # against the effective ARN raises a notification.<br/>    break_glass_role_arn = optional(string, "")<br/>    # Set of org-security services (org-security-service module) to enable: any of macie, inspector,<br/>    # detective, resource-explorer. Detective defaults OFF per SRA.<br/>    enabled_security_services = optional(set(string), ["macie", "inspector"])<br/>    # Master COST toggle for Amazon Security Lake. Security Lake incurs ingestion, storage, and<br/>    # normalization charges.<br/>    enable_security_lake = optional(bool, true)<br/>    # AWS Config records ALL supported resource types (default true — the full-coverage but most<br/>    # expensive Config mode). Set false for cost-sensitive non-prod (FinOps F5).<br/>    config_record_all_supported = optional(bool, true)<br/>    # GuardDuty agentless EBS malware scanning (default true; billed per GB scanned). Set false for<br/>    # non-prod where it is not required (FinOps F5).<br/>    guardduty_enable_ebs_malware_protection = optional(bool, true)<br/>    # Master switch for the incident-response automation (isolation Lambda, GuardDuty EventBridge<br/>    # rule, forensics snapshot-sharing role).<br/>    enable_incident_response = optional(bool, true)<br/>    # Master switch for service-quota management (opt-in). When false, no quota requests or usage<br/>    # alarms are created.<br/>    enable_service_quotas = optional(bool, false)<br/>    # Create the ORGANIZATION_INTERNAL_ACCESS analyzer (alongside the external one) in the home region<br/>    # and every enabled region. External analyzers are always created in every enabled region.<br/>    enable_internal_access_analyzer = optional(bool, true)<br/>    # Subscribers attached to the security-notifications SNS topic, keyed by an arbitrary name. At<br/>    # least one is required (findings would otherwise fire into a void). Defaults to a placeholder<br/>    # SecOps email the root is expected to override.<br/>    notification_subscribers = optional(map(object({<br/>      protocol = string # one of: email, https, sms, sqs, lambda, etc.<br/>      endpoint = string # e.g. an email address or HTTPS URL<br/>      })), {<br/>      secops = { protocol = "email", endpoint = "secops@example.com" }<br/>    })<br/>    # Dedicated identity account for IAM Identity Center delegated administration. Default null = the<br/>    # shared-services account (unchanged). Set to a dedicated identity account to tighten the<br/>    # delegated-admin blast radius. PREVIEW: opt-in (default off), not yet validated against a real<br/>    # apply.<br/>    identity_account_id = optional(string)<br/>    # Attach a CloudWatch Logs group to the org trail and create the full CIS AWS section-4 metric-<br/>    # filter alarm set (4.1-4.15) with a KMS-encrypted SNS topic, all in the management account. Self-<br/>    # sufficient: a logs-granted CMK is created when cloudwatch_logs_kms_key_arn is null. Default<br/>    # true; set false for S3-only delivery.<br/>    enable_cloudwatch_logs = optional(bool, true)<br/>    # Retention (days) for the CloudTrail CloudWatch Logs group when enable_cloudwatch_logs = true.<br/>    cloudwatch_logs_retention_days = optional(number, 365)<br/>    # Optional existing CMK ARN (management account) for the CloudTrail CloudWatch Logs group and CIS<br/>    # alarm topic; its policy must grant logs.<region>.amazonaws.com and cloudwatch.amazonaws.com.<br/>    # Null (default) = a dedicated CMK is created.<br/>    cloudwatch_logs_kms_key_arn = optional(string)<br/>    # Optional existing SNS topic ARN for the CIS alarms. Null (default) = a KMS-encrypted topic is<br/>    # created and subscribed with cloudtrail_alarm_subscribers.<br/>    cloudtrail_alarm_sns_topic_arn = optional(string)<br/>    # Subscribers of the CIS alarm topic. Null (default) = reuse notification_subscribers.<br/>    cloudtrail_alarm_subscribers = optional(map(object({<br/>      protocol = string<br/>      endpoint = string<br/>    })))<br/>    # CIS alarm keys to skip (see modules/aws/security/cloudtrail-org cis_alarms_excluded), e.g.<br/>    # ["unauthorized-api-calls"] if too noisy org-wide.<br/>    cloudtrail_cis_alarms_excluded = optional(list(string), [])<br/>    # S3 object-level data events on the org trail: none, write (CIS 3.8, default), read (CIS 3.9) or<br/>    # all. COST: billed per event across every org account.<br/>    cloudtrail_s3_data_events = optional(string, "write")<br/>    # Extra S3 bucket ARNs excluded from data events (the log-archive bucket is always excluded).<br/>    cloudtrail_s3_data_events_excluded_bucket_arns = optional(list(string), [])<br/>    # Record Lambda Invoke data events on the org trail (default false; per-invocation cost).<br/>    cloudtrail_lambda_data_events = optional(bool, false)<br/>    # Create and manage the break-glass role in the management account (opt-in), instead of<br/>    # referencing an external one. When true the role's ARN is wired into the assumption alarm<br/>    # automatically and exported.<br/>    create_break_glass = optional(bool, false)<br/>    # Name of the managed break-glass role (used only when create_break_glass is true). Its ARN is<br/>    # arn:aws:iam::<management-account>:role/<this name> — set the org SCP exemptions to match.<br/>    break_glass_role_name = optional(string, "OrganizationBreakGlass")<br/>    # Account-qualified ARNs permitted to assume the managed break-glass role (used only when<br/>    # create_break_glass is true). Keep this to a small set of senior responders. MFA is always<br/>    # required.<br/>    break_glass_trusted_principals = optional(list(string), [])<br/>    # Maximum age in seconds of the MFA session allowed to assume the managed break-glass role (used<br/>    # only when create_break_glass is true).<br/>    break_glass_mfa_max_age = optional(number, 3600)<br/>    # Set true ONLY during a declared incident to attach AdministratorAccess to the managed break-<br/>    # glass role. False (default) keeps the deny-all standing policy. Flipping this to true should<br/>    # itself be a reviewed, alarmed change.<br/>    break_glass_active = optional(bool, false)<br/>    # Create the organization CloudTrail (management account) with its CloudWatch Logs, CIS alarms and<br/>    # KMS wiring. Set false when another owner already runs the org trail, e.g. AWS Control Tower<br/>    # (docs/runbooks/aws-brownfield-adoption.md); two org trails double the cost and the noise.<br/>    # Default true.<br/>    create_organization_trail = optional(bool, true)<br/>    # Existing CloudTrail -> CloudWatch Logs delivery role (created by aws-organization,<br/>    # create_org_trail_delivery_role). Null = the cloudtrail-org module creates it, which needs IAM<br/>    # write in the management account.<br/>    cloudtrail_cloudwatch_role_arn = optional(string)<br/>  })</pre> | `{}` | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | Home (aggregation) Region. Used as the Security Hub home\_region for the region-scoped standard ARNs. | `string` | `"eu-west-2"` | no |
| <a name="input_backup_account_id"></a> [backup\_account\_id](#input\_backup\_account\_id) | Dedicated backup account, registered as the AWS Backup delegated administrator. Null = the security-tooling account. | `string` | `null` | no |
| <a name="input_cloudtrail_log_group_name"></a> [cloudtrail\_log\_group\_name](#input\_cloudtrail\_log\_group\_name) | Name of the CloudWatch Logs group the organization CloudTrail delivers into, in the security-tooling account. When set (with break\_glass\_role\_arn), the security-notifications control adds a metric-filter + CloudWatch metric ALARM on break-glass AssumeRole. Empty (default) leaves only the always-on EventBridge rule. | `string` | `""` | no |
| <a name="input_cloudwatch_logs_kms_key_manager_arns"></a> [cloudwatch\_logs\_kms\_key\_manager\_arns](#input\_cloudwatch\_logs\_kms\_key\_manager\_arns) | IAM role ARNs granted day-2 management (refresh, rotation, tags, aliases) of the module-created CloudWatch Logs CMK by its key policy. Null (default) = the aws-security management apply role (<management\_role\_name\_prefix>aws-security-apply) in the management account. [] = none. | `list(string)` | `null` | no |
| <a name="input_enable_firewall_manager"></a> [enable\_firewall\_manager](#input\_enable\_firewall\_manager) | Master switch for AWS Firewall Manager composition. Default false: registering the FMS administrator is an explicit, one-time decision, and the firewall-manager-org module ships a placeholder security-group policy that must be overridden before enabling. When true, the Security Tooling account is registered as FMS admin from the management account. | `bool` | `false` | no |
| <a name="input_key_policy_admin_role_name"></a> [key\_policy\_admin\_role\_name](#input\_key\_policy\_admin\_role\_name) | Role name (optionally path-prefixed), in each CMK's OWN account, granted kms:PutKeyPolicy — and nothing else — on the log-archive, forensics and security-tooling CMKs. Default break-glass: the member break-glass role the aws-organization stage deploys to every member account (enable\_member\_break\_glass\_role), so the pipeline key admin cannot rewrite a key policy to grant itself kms:Decrypt. The role must exist before this stage creates the keys (KMS rejects unknown principals), and later key-policy changes must be applied as it. Null = legacy: key admin also holds PutKeyPolicy. | `string` | `"break-glass"` | no |
| <a name="input_management_role_name_prefix"></a> [management\_role\_name\_prefix](#input\_management\_role\_name\_prefix) | Prefix of the management-account tfc-management-roles role names, used to derive the aws-security apply role ARN when cloudwatch\_logs\_kms\_key\_manager\_arns is null. Must match the aws-organization tfc\_management\_roles role\_name\_prefix. | `string` | `"tfc-mgmt-"` | no |
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
