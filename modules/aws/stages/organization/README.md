# aws-organization stage

Thin orchestration wrapper that composes the AWS control-plane primitives into a
complete SRA landing-zone organization:

- **organization** — the AWS organization, SRA OU topology, enabled policy
  types, and trusted-service access.
- **account** (`for_each`) — the six foundational member accounts
  (`log_archive`, `security_tooling`, `network`, `shared_services`, `backup`,
  `forensics`) plus any caller-supplied `workload_accounts`.
- **organization-policy** — the guardrail policy set (three SCPs, a
  data-perimeter RCP, a declarative EC2 policy, a tag policy) attached to the
  root and the Workloads OU. The backup policy is authored here but attached
  later (Epic H).
- **iam-organizations-features** — centralized root-access management.

OU topology, enabled policy types and trusted-service principals use the
`organization` module's SRA defaults. Callers must supply the account-qualified
carve-out ARNs (`terraform_run_role_arn`, `break_glass_role_arn`) and the
`log_archive_bucket_name`; the default account emails are placeholders the root
is expected to override.

The stage exports the stable cross-root contract consumed by later stages:
`organization_id`, `management_account_id`, `ou_ids`, `account_ids`,
`account_role_arns`, and `policy_attachment_ids`.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	break_glass_role_arn =
	log_archive_bucket_name =
	terraform_run_role_arn =
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
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.72.0 |

## Modules


- account - ../../governance/account
- cost_governance - ../../governance/cost-governance
- management_config_recorder - ../../security/config-org
- org_config_recorders - ../../security/config-recorder-stackset
- organization - ../../governance/organization
- policies - ../../governance/organization-policy
- root_access - ../../governance/iam-organizations-features
- tfc_management_roles - ../../iam/tfc-management-roles
- tfc_oidc_baseline - ../../iam/tfc-oidc-baseline


## Resources

The following resources are created:


- resource.aws_cloudformation_stack_set.backup_service_role (modules/aws/stages/organization/backup_role.tf#L35)
- resource.aws_cloudformation_stack_set_instance.backup_service_role (modules/aws/stages/organization/backup_role.tf#L64)
- resource.aws_cloudtrail_organization_delegated_admin_account.this (modules/aws/stages/organization/cloudtrail_delegation.tf#L20)
- resource.aws_cloudwatch_event_rule.guard_alerts (modules/aws/stages/organization/guard_alerts.tf#L218)
- resource.aws_cloudwatch_event_rule.guard_alerts_forward (modules/aws/stages/organization/guard_alerts.tf#L261)
- resource.aws_cloudwatch_event_target.guard_alerts (modules/aws/stages/organization/guard_alerts.tf#L226)
- resource.aws_cloudwatch_event_target.guard_alerts_forward (modules/aws/stages/organization/guard_alerts.tf#L271)
- resource.aws_iam_role.guard_alerts_forwarder (modules/aws/stages/organization/guard_alerts.tf#L235)
- resource.aws_iam_role.org_trail_cloudwatch (modules/aws/stages/organization/trail_delivery_role.tf#L7)
- resource.aws_iam_role_policy.guard_alerts_forwarder (modules/aws/stages/organization/guard_alerts.tf#L248)
- resource.aws_iam_role_policy.org_trail_cloudwatch (modules/aws/stages/organization/trail_delivery_role.tf#L24)
- resource.aws_kms_alias.guard_alerts (modules/aws/stages/organization/guard_alerts.tf#L156)
- resource.aws_kms_key.guard_alerts (modules/aws/stages/organization/guard_alerts.tf#L127)
- resource.aws_organizations_delegated_administrator.identity_center (modules/aws/stages/organization/identity_center_delegation.tf#L5)
- resource.aws_sns_topic.guard_alerts (modules/aws/stages/organization/guard_alerts.tf#L163)
- resource.aws_sns_topic_policy.guard_alerts (modules/aws/stages/organization/guard_alerts.tf#L179)
- resource.aws_sns_topic_subscription.guard_alerts (modules/aws/stages/organization/guard_alerts.tf#L208)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_break_glass_role_arn"></a> [break\_glass\_role\_arn](#input\_break\_glass\_role\_arn) | Account-qualified exact ARN of the emergency break-glass role. Carved out of every guardrail deny statement. | `string` | n/a | yes |
| <a name="input_log_archive_bucket_name"></a> [log\_archive\_bucket\_name](#input\_log\_archive\_bucket\_name) | Name of the central log-archive S3 bucket protected from Object Lock / governance-retention tampering by the deny-tamper SCP. | `string` | n/a | yes |
| <a name="input_terraform_run_role_arn"></a> [terraform\_run\_role\_arn](#input\_terraform\_run\_role\_arn) | Account-qualified exact ARN of the Terraform Cloud run role. Carved out of every guardrail deny statement so automation is not locked out. | `string` | n/a | yes |
| <a name="input_accounts"></a> [accounts](#input\_accounts) | Foundational member accounts to create, keyed by account name. Each entry sets the root email, the target OU name (must exist in the organization OU tree), optional alternate contacts, and optional tags. Defaults to the six SRA foundational accounts with placeholder emails the root is expected to override. | <pre>map(object({<br/>    email = string<br/>    ou    = string<br/>    # Display name of the account. Null = the map key. Set it when adopting an<br/>    # existing account whose name differs from the key (adopt_existing).<br/>    name = optional(string)<br/>    alternate_contacts = optional(map(object({<br/>      contact_type  = string<br/>      name          = string<br/>      title         = string<br/>      email_address = string<br/>      phone_number  = string<br/>    })), {})<br/>    tags = optional(map(string), {})<br/>  }))</pre> | <pre>{<br/>  "backup": {<br/>    "email": "aws+backup@example.com",<br/>    "ou": "Infrastructure"<br/>  },<br/>  "forensics": {<br/>    "email": "aws+forensics@example.com",<br/>    "ou": "Security"<br/>  },<br/>  "log_archive": {<br/>    "email": "aws+log-archive@example.com",<br/>    "ou": "Security"<br/>  },<br/>  "network": {<br/>    "email": "aws+network@example.com",<br/>    "ou": "Infrastructure"<br/>  },<br/>  "security_tooling": {<br/>    "email": "aws+security-tooling@example.com",<br/>    "ou": "Security"<br/>  },<br/>  "shared_services": {<br/>    "email": "aws+shared-services@example.com",<br/>    "ou": "Infrastructure"<br/>  }<br/>}</pre> | no |
| <a name="input_allow_vpc_bpa_exclusions"></a> [allow\_vpc\_bpa\_exclusions](#input\_allow\_vpc\_bpa\_exclusions) | Whether member accounts may create VPC Block Public Access exclusions under the declarative EC2 policy. Default false. | `bool` | `false` | no |
| <a name="input_allowed_builtin_web_identity_providers"></a> [allowed\_builtin\_web\_identity\_providers](#input\_allowed\_builtin\_web\_identity\_providers) | Built-in web-identity providers roles may trust (cognito-identity.amazonaws.com, accounts.google.com, graph.facebook.com, www.amazon.com). Default none: the RCP denies sts:AssumeRoleWithWebIdentity with their tokens, since they need no IAM provider resource and so escape every other control. | `list(string)` | `[]` | no |
| <a name="input_allowed_regions"></a> [allowed\_regions](#input\_allowed\_regions) | Regions permitted by the region-restriction SCP. Requests to any other region are denied (global services are carved out). | `list(string)` | <pre>[<br/>  "eu-west-2"<br/>]</pre> | no |
| <a name="input_aws_enabled_regions"></a> [aws\_enabled\_regions](#input\_aws\_enabled\_regions) | Regions in which the regional security services run (the aws-security root's aws\_enabled\_regions). Every one except us-east-1 gets an EventBridge rule forwarding org-detection guard events to us-east-1. | `list(string)` | <pre>[<br/>  "eu-west-2"<br/>]</pre> | no |
| <a name="input_backup_service_role_name"></a> [backup\_service\_role\_name](#input\_backup\_service\_role\_name) | Name of the member-account AWS Backup service role (must equal aws-backup backup\_role\_name). | `string` | `"aws-backup-org-role"` | no |
| <a name="input_backup_service_role_region"></a> [backup\_service\_role\_region](#input\_backup\_service\_role\_region) | Region of the Backup service-role stack instances (IAM is global; one region suffices). | `string` | `"eu-west-2"` | no |
| <a name="input_backup_service_role_stack_set_name"></a> [backup\_service\_role\_stack\_set\_name](#input\_backup\_service\_role\_stack\_set\_name) | Name of the StackSet that deploys the Backup service role. | `string` | `"aws-backup-org-role"` | no |
| <a name="input_break_glass_role_names"></a> [break\_glass\_role\_names](#input\_break\_glass\_role\_names) | Member-account break-glass role names for the deny-tamper SCP (sole exemption from the destructive statements). Empty (default) derives the name from break\_glass\_role\_arn. | `list(string)` | `[]` | no |
| <a name="input_budgets"></a> [budgets](#input\_budgets) | Monthly COST budgets keyed by budget name, passed to the cost-governance module. limit\_amount is the USD limit; threshold\_percent triggers an ACTUAL-spend notification; emails receive the notification. | <pre>map(object({<br/>    limit_amount      = string<br/>    threshold_percent = number<br/>    emails            = optional(list(string), [])<br/>    alert_percents    = optional(list(number), [])<br/>  }))</pre> | <pre>{<br/>  "org-monthly": {<br/>    "limit_amount": "1000",<br/>    "threshold_percent": 80<br/>  }<br/>}</pre> | no |
| <a name="input_central_detection_account_keys"></a> [central\_detection\_account\_keys](#input\_central\_detection\_account\_keys) | Account keys (from accounts) whose pipeline may change GuardDuty filters/detectors, CloudTrail selectors and Security Hub standards; denied everywhere else except break-glass (deny-tamper SCP). Default: the SRA security\_tooling and log\_archive accounts. Set [] to restore the pipeline-wide exemption. | `list(string)` | <pre>[<br/>  "security_tooling",<br/>  "log_archive"<br/>]</pre> | no |
| <a name="input_cost_allocation_tags"></a> [cost\_allocation\_tags](#input\_cost\_allocation\_tags) | Tag keys to activate as cost-allocation tags in Cost Explorer / the Cost & Usage Report. Should mirror the tag-policy keys. | `list(string)` | <pre>[<br/>  "CostCenter",<br/>  "Environment",<br/>  "Owner"<br/>]</pre> | no |
| <a name="input_cost_anomaly_email"></a> [cost\_anomaly\_email](#input\_cost\_anomaly\_email) | Email address that receives Cost Anomaly Detection alerts. | `string` | `"finops@example.com"` | no |
| <a name="input_cost_notifications_topic_arn"></a> [cost\_notifications\_topic\_arn](#input\_cost\_notifications\_topic\_arn) | Optional SNS topic ARN that budget notifications are published to, in addition to per-budget email subscribers. Empty string disables SNS fan-out. | `string` | `""` | no |
| <a name="input_create_backup_service_role"></a> [create\_backup\_service\_role](#input\_create\_backup\_service\_role) | Deploy the member-account AWS Backup service role (backup\_service\_role\_name) to every Workloads-OU account through a service-managed StackSet. aws-backup's BACKUP\_POLICY references it, so aws-backup needs no CloudFormation rights. Default true. | `bool` | `true` | no |
| <a name="input_create_management_config_service_linked_role"></a> [create\_management\_config\_service\_linked\_role](#input\_create\_management\_config\_service\_linked\_role) | With enable\_org\_config\_recorders, create the AWSServiceRoleForConfig service-linked role in the management account. Set false when Config was enabled there before (the role already exists). | `bool` | `true` | no |
| <a name="input_create_org_trail_delivery_role"></a> [create\_org\_trail\_delivery\_role](#input\_create\_org\_trail\_delivery\_role) | Create the organization trail's CloudTrail -> CloudWatch Logs delivery role (<org\_trail\_name>-cloudwatch-delivery) here, so aws-security needs no IAM write in the management account. Default true. | `bool` | `true` | no |
| <a name="input_data_perimeter_trusted_account_ids"></a> [data\_perimeter\_trusted\_account\_ids](#input\_data\_perimeter\_trusted\_account\_ids) | Optional 12-digit account IDs outside the organization trusted by the RCP data perimeter (aws:PrincipalAccount / aws:SourceAccount). Empty (default) trusts only the organization. | `list(string)` | `[]` | no |
| <a name="input_disabled_org_policies"></a> [disabled\_org\_policies](#input\_disabled\_org\_policies) | Built-in policy keys not to create; their default attachments are dropped too. Default: backup-policy (the aws-backup stage owns the attached BACKUP\_POLICY, so the built-in copy would sit unattached). | `list(string)` | <pre>[<br/>  "backup-policy"<br/>]</pre> | no |
| <a name="input_ec2_allowed_images"></a> [ec2\_allowed\_images](#input\_ec2\_allowed\_images) | Declarative EC2 Allowed AMIs setting, in the root-attached baseline declarative policy (every account, every region). state: audit\_mode (default; records non-compliant AMIs, blocks nothing), enabled (blocks launches from other AMIs), disabled, or unmanaged (the policy carries no allowed-images setting). allowed\_image\_providers: amazon, aws\_marketplace, aws\_backup\_vault or 12-digit account IDs. Move to enabled only after reviewing the audit-mode findings. | <pre>object({<br/>    state                   = optional(string, "audit_mode")<br/>    allowed_image_providers = optional(list(string), ["amazon"])<br/>  })</pre> | `{}` | no |
| <a name="input_enable_cloudtrail_delegated_admin"></a> [enable\_cloudtrail\_delegated\_admin](#input\_enable\_cloudtrail\_delegated\_admin) | Register the security\_tooling account as the CloudTrail delegated administrator (aws\_cloudtrail\_organization\_delegated\_admin\_account, which also creates the CloudTrail service-linked roles), so aws-security creates and manages the organization trail from security tooling under the deny-tamper SCP. Also strips every trail write from the aws-security management role. Set the same value in aws-security. Default false: the management account manages the trail, unchanged. Migration: docs/runbooks/aws-cloudtrail-delegated-admin-migration.md. | `bool` | `false` | no |
| <a name="input_enable_config_recorder_scp"></a> [enable\_config\_recorder\_scp](#input\_enable\_config\_recorder\_scp) | Deny Config recorder changes (Put/Delete/StopConfigurationRecorder, DeleteDeliveryChannel) to every member principal except the StackSet execution role, break-glass and security tooling's tfc-apply (deny-tamper DenyConfigRecorderChanges). Default false: until the migration finishes, the workload pipelines still own recorders. Turn it on at the last step of the migration runbook. | `bool` | `false` | no |
| <a name="input_enable_cost_governance"></a> [enable\_cost\_governance](#input\_enable\_cost\_governance) | Gate for the cost-governance module (budgets, Cost Anomaly Detection, cost-allocation tags). When false the module composes as a no-op. | `bool` | `true` | no |
| <a name="input_enable_member_break_glass_role"></a> [enable\_member\_break\_glass\_role](#input\_enable\_member\_break\_glass\_role) | Deploy the break-glass role into every member account (sibling StackSet of the TFC OIDC baseline, targeting the org root) so the SCP-exempt break-glass name is occupied and protected there instead of claimable by the first principal to create it. Rides on enable\_tfc\_oidc\_baseline. Default true. | `bool` | `true` | no |
| <a name="input_enable_org_config_recorders"></a> [enable\_org\_config\_recorders](#input\_enable\_org\_config\_recorders) | Deploy AWS Config recorders org-wide: a service-managed StackSet to every member account except security\_tooling (which keeps its aggregator recorder), plus a direct recorder in the management account. Default false: the delivery bucket comes from aws-security, which applies after aws-organization. Turn it on after aws-security has applied (greenfield) or at step 3 of the migration runbook. | `bool` | `false` | no |
| <a name="input_enable_security_service_teardown"></a> [enable\_security\_service\_teardown](#input\_enable\_security\_service\_teardown) | Teardown gate for the aws-security management apply role: allow it to disable the security services' delegated admins and trusted access. Default false; set true only for a reviewed aws-security destroy (docs/runbooks/aws-teardown.md), then back to false. | `bool` | `false` | no |
| <a name="input_enable_tfc_management_roles"></a> [enable\_tfc\_management\_roles](#input\_enable\_tfc\_management\_roles) | Create a dedicated least-privilege management-account plan/apply role pair per management-default workspace (tfc\_management\_workspaces). tfc-admin binds them instead of the shared phase-0 management role, so aws-security / aws-backup cannot pivot into member accounts or change the org structure. Requires tfc\_organization and the management account's TFC OIDC provider (phase 0). Default true. | `bool` | `true` | no |
| <a name="input_enable_tfc_oidc_baseline"></a> [enable\_tfc\_oidc\_baseline](#input\_enable\_tfc\_oidc\_baseline) | Gate for the TFC OIDC baseline StackSet (OIDC provider + tfc-plan/tfc-apply roles in member accounts). Requires tfc\_organization when true. | `bool` | `true` | no |
| <a name="input_github_federation_owner_ids"></a> [github\_federation\_owner\_ids](#input\_github\_federation\_owner\_ids) | Numeric GitHub owner IDs whose Actions tokens may assume roles (RCP pin repository\_owner\_id:<id>:*), for deploy roles using the immutable-ID subject template. Complements github\_federation\_owners. | `list(string)` | `[]` | no |
| <a name="input_github_federation_owners"></a> [github\_federation\_owners](#input\_github\_federation\_owners) | GitHub users/orgs whose Actions OIDC tokens may assume roles anywhere in the organization (RCP pin: sub must be repo:<owner>/*). Empty (default) leaves GitHub federation unpinned. Set it to every owner whose repos deploy here (app-services deploy roles). | `list(string)` | `[]` | no |
| <a name="input_guard_alert_emails"></a> [guard\_alert\_emails](#input\_guard\_alert\_emails) | Email addresses subscribed to the org-guard-alerts SNS topic (us-east-1, management account): alerts when org-wide detection is disabled or the organization trail's selectors / tags change. Each address must confirm its subscription. Empty = topic and rules only. | `list(string)` | `[]` | no |
| <a name="input_identity_center_admin_account_key"></a> [identity\_center\_admin\_account\_key](#input\_identity\_center\_admin\_account\_key) | Account key (accounts / workload\_accounts) to register as the IAM Identity Center delegated administrator. Default shared\_services, the aws-identity account in the SRA layout. Null = do not register here. | `string` | `"shared_services"` | no |
| <a name="input_member_break_glass_require_mfa"></a> [member\_break\_glass\_require\_mfa](#input\_member\_break\_glass\_require\_mfa) | Require MFA (aws:MultiFactorAuthPresent + aws:MultiFactorAuthAge) on the member break-glass trust. Default true. A role-chained session may not carry MFA context: trust MFA-authenticated IAM users, or set false when the trusted management role is itself MFA-gated — validate end to end before relying on it. | `bool` | `true` | no |
| <a name="input_member_break_glass_trusted_principal_arns"></a> [member\_break\_glass\_trusted\_principal\_arns](#input\_member\_break\_glass\_trusted\_principal\_arns) | Account-qualified management-account principal ARNs (role or user) the member break-glass role trusts. Empty (default) = [break\_glass\_role\_arn]. | `list(string)` | `[]` | no |
| <a name="input_org_config_recorders_failure_tolerance_percentage"></a> [org\_config\_recorders\_failure\_tolerance\_percentage](#input\_org\_config\_recorders\_failure\_tolerance\_percentage) | Failure tolerance of the recorder StackSet operations. 0 (default) for routine runs. The migration pass sets 100 so the instances that fail in accounts still holding a legacy recorder do not fail the apply; set it back to 0 afterwards. | `number` | `0` | no |
| <a name="input_org_policy_attachments"></a> [org\_policy\_attachments](#input\_org\_policy\_attachments) | Extra policy attachments (key => {policy\_key, target\_id}), e.g. for policies added through org\_policy\_overrides. Keys must not collide with the built-in attachment keys. | <pre>map(object({<br/>    policy_key = string<br/>    target_id  = string<br/>  }))</pre> | `{}` | no |
| <a name="input_org_policy_overrides"></a> [org\_policy\_overrides](#input\_org\_policy\_overrides) | Organization policies merged over the built-in guardrail set (organization-policy policy\_overrides): an existing key replaces that policy's content, a new key adds one (attach it with org\_policy\_attachments). Use this instead of forking the stage. | <pre>map(object({<br/>    type    = string<br/>    content = string<br/>  }))</pre> | `{}` | no |
| <a name="input_org_trail_home_region"></a> [org\_trail\_home\_region](#input\_org\_trail\_home\_region) | Home region of the organization trail (the aws-security root's aws\_region): its log group, CIS alarms and alarm topic live there, so it always gets a guard-alert forwarding rule even if absent from aws\_enabled\_regions. | `string` | `"eu-west-2"` | no |
| <a name="input_org_trail_name"></a> [org\_trail\_name](#input\_org\_trail\_name) | Name of the organization CloudTrail trail aws-security creates (cloudtrail-org trail\_name). | `string` | `"org-trail"` | no |
| <a name="input_partition"></a> [partition](#input\_partition) | AWS partition the organization policies are rendered for (aws, aws-us-gov, aws-cn). | `string` | `"aws"` | no |
| <a name="input_pin_tfc_federation_to_org"></a> [pin\_tfc\_federation\_to\_org](#input\_pin\_tfc\_federation\_to\_org) | Deny (RCP, every account) sts:AssumeRoleWithWebIdentity with a <tfc\_hostname> token whose sub is not organization:<tfc\_organization>:*. Without it, any pipeline that can create a role can make it trust ANOTHER TFC org on the same issuer: a persistence path no permissions boundary sees. Default true; takes effect when tfc\_organization is set. Set false only if workspaces in other TFC organizations must assume roles here. | `bool` | `true` | no |
| <a name="input_pipeline_role_names"></a> [pipeline\_role\_names](#input\_pipeline\_role\_names) | Member-account Terraform pipeline role names (or name patterns) passed to the deny-tamper SCP. Rendered as arn:aws:iam::*:role/<name>: exempt from the security-service reconfiguration denies and protected from IAM modification. SCPs never apply to the management account, so these must be the roles that run IN member accounts. | `list(string)` | <pre>[<br/>  "tfc-apply",<br/>  "OrganizationAccountAccessRole",<br/>  "stacksets-exec-*"<br/>]</pre> | no |
| <a name="input_sandbox_allowed_instance_types"></a> [sandbox\_allowed\_instance\_types](#input\_sandbox\_allowed\_instance\_types) | ec2:InstanceType patterns the Sandbox OU may launch (scp-sandbox-guard denies ec2:RunInstances for any other type). | `list(string)` | <pre>[<br/>  "t3.micro",<br/>  "t3.small",<br/>  "t3.medium",<br/>  "t3.large",<br/>  "t4g.micro",<br/>  "t4g.small",<br/>  "t4g.medium",<br/>  "t4g.large"<br/>]</pre> | no |
| <a name="input_security_tooling_apply_role_name"></a> [security\_tooling\_apply\_role\_name](#input\_security\_tooling\_apply\_role\_name) | Name (optionally path-prefixed) of the security-tooling pipeline role that manages the aggregator recorder: the only pipeline role exempt from the recorder SCP, as arn:<partition>:iam::<security\_tooling>:role/<name>. Default tfc-apply (tfc-oidc-baseline). | `string` | `"tfc-apply"` | no |
| <a name="input_tfc_apply_permissions_boundary_arn"></a> [tfc\_apply\_permissions\_boundary\_arn](#input\_tfc\_apply\_permissions\_boundary\_arn) | Optional existing permissions-boundary policy ARN for the tfc-apply roles (must exist in every bound account). Null (default) = the embedded tfc-apply-boundary. | `string` | `null` | no |
| <a name="input_tfc_apply_role_policy_arns"></a> [tfc\_apply\_role\_policy\_arns](#input\_tfc\_apply\_role\_policy\_arns) | Managed policy ARNs attached to every member-account tfc-apply role (capped by the apply permissions boundary, tfc\_enable\_apply\_permissions\_boundary). | `list(string)` | <pre>[<br/>  "arn:aws:iam::aws:policy/AdministratorAccess"<br/>]</pre> | no |
| <a name="input_tfc_enable_apply_boundary_propagation"></a> [tfc\_enable\_apply\_boundary\_propagation](#input\_tfc\_enable\_apply\_boundary\_propagation) | Make the embedded tfc-apply boundary self-propagating (default true): tfc-apply can only create / grant to roles carrying the same boundary and can never remove a boundary, closing the create-unbounded-role escape. Every aws\_iam\_role created by tfc-apply in a member account must then set permissions\_boundary to the tfc-apply-boundary ARN. | `bool` | `true` | no |
| <a name="input_tfc_enable_apply_permissions_boundary"></a> [tfc\_enable\_apply\_permissions\_boundary](#input\_tfc\_enable\_apply\_permissions\_boundary) | Cap every member-account tfc-apply role with a permissions boundary (default true). With tfc\_apply\_permissions\_boundary\_arn = null the StackSet embeds tfc-apply-boundary: allow-all except leaving the org, stopping/deleting CloudTrail/GuardDuty/Config, modifying the TFC roles/OIDC provider/boundary, creating IAM users/access keys, and (tfc\_enable\_apply\_boundary\_propagation) creating or granting to roles without the same boundary. | `bool` | `true` | no |
| <a name="input_tfc_enable_plan_role_data_read_deny"></a> [tfc\_enable\_plan\_role\_data\_read\_deny](#input\_tfc\_enable\_plan\_role\_data\_read\_deny) | Attach an inline deny on data-plane reads (s3:GetObject*, secretsmanager:GetSecretValue, ssm:GetParameter*, kms:Decrypt, DynamoDB/SQS/Kinesis/Logs reads, ...) to every member-account tfc-plan role (default true). | `bool` | `true` | no |
| <a name="input_tfc_hostname"></a> [tfc\_hostname](#input\_tfc\_hostname) | Terraform Cloud / Enterprise hostname issuing the workload-identity tokens. | `string` | `"app.terraform.io"` | no |
| <a name="input_tfc_management_workspaces"></a> [tfc\_management\_workspaces](#input\_tfc\_management\_workspaces) | Management-default workspaces that get their own role pair (tfc-management-roles workspaces). aws-security and aws-backup have built-in least-privilege policies; others need apply\_policy\_json. | <pre>map(object({<br/>    project           = optional(string)<br/>    apply_policy_json = optional(string)<br/>  }))</pre> | <pre>{<br/>  "aws-backup": {},<br/>  "aws-security": {}<br/>}</pre> | no |
| <a name="input_tfc_oidc_allow_workspace_wildcards"></a> [tfc\_oidc\_allow\_workspace\_wildcards](#input\_tfc\_oidc\_allow\_workspace\_wildcards) | Allow '*' inside bound workspace names (StringLike sub match). The organization and project are always literal. Default false: exact workspace names. | `bool` | `false` | no |
| <a name="input_tfc_oidc_call_as"></a> [tfc\_oidc\_call\_as](#input\_tfc\_oidc\_call\_as) | Manage the StackSet as the management account (SELF) or a CloudFormation delegated administrator (DELEGATED\_ADMIN). | `string` | `"SELF"` | no |
| <a name="input_tfc_organization"></a> [tfc\_organization](#input\_tfc\_organization) | Terraform Cloud organization whose workspaces the member-account roles trust (matched literally, never wildcarded). Required when enable\_tfc\_oidc\_baseline is true. | `string` | `null` | no |
| <a name="input_tfc_plan_role_data_read_exempt_arns"></a> [tfc\_plan\_role\_data\_read\_exempt\_arns](#input\_tfc\_plan\_role\_data\_read\_exempt\_arns) | Resource ARNs excluded from the tfc-plan data-plane deny (NotResource), for Terraform-managed resources whose refresh reads data (e.g. the aws-workload SaaS bridge secret). Empty (default) = deny everywhere. | `list(string)` | `[]` | no |
| <a name="input_tfc_project"></a> [tfc\_project](#input\_tfc\_project) | Default TFC project of the bound workspaces (matched literally in the trust sub). Override per account with tfc\_workspace\_bindings[*].project. | `string` | `"Default Project"` | no |
| <a name="input_tfc_workspace_bindings"></a> [tfc\_workspace\_bindings](#input\_tfc\_workspace\_bindings) | Map of account key (from accounts / workload\_accounts) -> TFC workspaces allowed to assume that account's tfc-plan / tfc-apply roles, with an optional project override. Add one entry per workload account, e.g. workload\_dev = { workspaces = ["aws-workload-dev"] }. The multi-account aws-security root is bound into security\_tooling, log\_archive and forensics; aws-backup into backup. | <pre>map(object({<br/>    workspaces = list(string)<br/>    project    = optional(string)<br/>  }))</pre> | <pre>{<br/>  "backup": {<br/>    "workspaces": [<br/>      "aws-backup"<br/>    ]<br/>  },<br/>  "forensics": {<br/>    "workspaces": [<br/>      "aws-security"<br/>    ]<br/>  },<br/>  "log_archive": {<br/>    "workspaces": [<br/>      "aws-security"<br/>    ]<br/>  },<br/>  "network": {<br/>    "workspaces": [<br/>      "aws-network"<br/>    ]<br/>  },<br/>  "security_tooling": {<br/>    "workspaces": [<br/>      "aws-security"<br/>    ]<br/>  },<br/>  "shared_services": {<br/>    "workspaces": [<br/>      "aws-identity",<br/>      "aws-shared-services"<br/>    ]<br/>  }<br/>}</pre> | no |
| <a name="input_workload_accounts"></a> [workload\_accounts](#input\_workload\_accounts) | Additional workload member accounts to create, keyed by account name. Merged with var.accounts; same object shape. | <pre>map(object({<br/>    email = string<br/>    ou    = string<br/>    # Display name of the account. Null = the map key. Set it when adopting an<br/>    # existing account whose name differs from the key (adopt_existing).<br/>    name = optional(string)<br/>    alternate_contacts = optional(map(object({<br/>      contact_type  = string<br/>      name          = string<br/>      title         = string<br/>      email_address = string<br/>      phone_number  = string<br/>    })), {})<br/>    tags = optional(map(string), {})<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_account_ids"></a> [account\_ids](#output\_account\_ids) | Map of member-account name to account ID. |
| <a name="output_account_role_arns"></a> [account\_role\_arns](#output\_account\_role\_arns) | Map of member-account name to its cross-account access role ARN. |
| <a name="output_cloudtrail_delegated_admin_account_id"></a> [cloudtrail\_delegated\_admin\_account\_id](#output\_cloudtrail\_delegated\_admin\_account\_id) | Account registered as the CloudTrail delegated administrator (security tooling) when enable\_cloudtrail\_delegated\_admin is true, else null. |
| <a name="output_cost_budget_ids"></a> [cost\_budget\_ids](#output\_cost\_budget\_ids) | Map of budget name to budget resource ID created by the cost-governance module. Empty when cost governance is disabled. |
| <a name="output_guard_alerts_topic_arn"></a> [guard\_alerts\_topic\_arn](#output\_guard\_alerts\_topic\_arn) | ARN of the org-guard-alerts SNS topic (us-east-1, management account): org-detection teardown and organization-trail tampering alerts. |
| <a name="output_management_account_id"></a> [management\_account\_id](#output\_management\_account\_id) | The account ID of the organization management (payer) account. |
| <a name="output_member_break_glass_stack_set_name"></a> [member\_break\_glass\_stack\_set\_name](#output\_member\_break\_glass\_stack\_set\_name) | Name of the StackSet deploying the break-glass role into member accounts, or null when disabled. |
| <a name="output_org_config_recorder_stack_set_name"></a> [org\_config\_recorder\_stack\_set\_name](#output\_org\_config\_recorder\_stack\_set\_name) | Name of the org-wide Config recorder StackSet, or null when enable\_org\_config\_recorders = false. |
| <a name="output_org_trail_cloudwatch_role_arn"></a> [org\_trail\_cloudwatch\_role\_arn](#output\_org\_trail\_cloudwatch\_role\_arn) | ARN of the organization trail's CloudWatch Logs delivery role (null when create\_org\_trail\_delivery\_role is false). |
| <a name="output_organization_id"></a> [organization\_id](#output\_organization\_id) | The ID of the AWS organization. |
| <a name="output_organization_root_id"></a> [organization\_root\_id](#output\_organization\_root\_id) | The ID of the organization root (r-xxxx), under which the top-level OUs are created. Consumed by the aws-security root as the Security Hub configuration-policy association target. |
| <a name="output_ou_ids"></a> [ou\_ids](#output\_ou\_ids) | Map of OU name (or parent/name path for child OUs) to OU ID. |
| <a name="output_policy_attachment_ids"></a> [policy\_attachment\_ids](#output\_policy\_attachment\_ids) | Map of guardrail attachment key to the attachment resource ID. |
| <a name="output_tfc_apply_role_arns"></a> [tfc\_apply\_role\_arns](#output\_tfc\_apply\_role\_arns) | Map of account key -> member-account tfc-apply role ARN. Set as TFC\_AWS\_APPLY\_ROLE\_ARN on the workspaces bound to that account. Empty when the TFC OIDC baseline is disabled. |
| <a name="output_tfc_management_apply_role_arns"></a> [tfc\_management\_apply\_role\_arns](#output\_tfc\_management\_apply\_role\_arns) | Workspace name -> dedicated management-account APPLY role ARN. Empty when enable\_tfc\_management\_roles is false. |
| <a name="output_tfc_management_plan_role_arns"></a> [tfc\_management\_plan\_role\_arns](#output\_tfc\_management\_plan\_role\_arns) | Workspace name -> dedicated management-account PLAN role ARN (aws-security, aws-backup). Empty when enable\_tfc\_management\_roles is false. |
| <a name="output_tfc_oidc_stack_set_name"></a> [tfc\_oidc\_stack\_set\_name](#output\_tfc\_oidc\_stack\_set\_name) | Name of the StackSet deploying the TFC OIDC baseline, or null when disabled. |
| <a name="output_tfc_plan_role_arns"></a> [tfc\_plan\_role\_arns](#output\_tfc\_plan\_role\_arns) | Map of account key -> member-account tfc-plan (read-only) role ARN. Set as TFC\_AWS\_PLAN\_ROLE\_ARN on the workspaces bound to that account. Empty when the TFC OIDC baseline is disabled. |
| <a name="output_tfc_workspace_bindings"></a> [tfc\_workspace\_bindings](#output\_tfc\_workspace\_bindings) | Map of account key -> TFC workspace names bound to that account's tfc-plan / tfc-apply roles (empty when the baseline is disabled). |
<!-- END_TF_DOCS -->
