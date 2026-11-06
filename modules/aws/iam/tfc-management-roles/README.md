# tfc-management-roles

Per-workspace, least-privilege Terraform Cloud roles in the AWS **management** account, for the
roots whose default provider is the management account besides `aws-organization`:

| Workspace | Apply role may | Explicitly denied |
|---|---|---|
| `aws-security` | Register/deregister delegated admins for the security services only (`organizations:ServicePrincipal` allow-list: no `sso`, no StackSets), manage **the** organization trail (scoped to its ARN) and its Logs/SNS/KMS/alarm wiring, and **pass** (never create or edit) the trail's CloudWatch delivery role, which aws-organization creates. It has no IAM role writes at all: in the management account every role write is an escalation path | Account create/close/move, OU changes, leaving/deleting the org, IAM users/keys, new identity providers, assuming `OrganizationAccountAccessRole` or member `tfc-*` roles, editing any `tfc-mgmt-*` role |
| `aws-backup` | Create/update/attach **`BACKUP_POLICY`** organization policies only (`organizations:PolicyType` condition), enable backup service access | Same denies, plus no IAM role management at all |

Each role trusts **one workspace and one run phase** with an exact `StringEquals` subject
(`organization:<org>:project:<project>:workspace:<ws>:run_phase:<plan|apply>`). Plan roles are
`ReadOnlyAccess` plus the same deny guard.

Without this module every management-default root shares the phase-0 management admin role. The
management account sits outside every SCP, so a change merged to `envs/aws/backup` could assume
`OrganizationAccountAccessRole` into every member account.

The `aws-organization` root creates these roles (`enable_tfc_management_roles`, default true) and
outputs their ARNs. `envs/tfc-admin` binds each workspace to its own pair. The allow lists are
derived from the resources the security and backup stages manage in the management account. They
have **not been validated against a real organization**. If an apply is denied, extend the allow
list through `workspaces[*].apply_policy_json` rather than falling back to the shared admin role.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	tfc_organization =
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



## Resources

The following resources are created:


- resource.aws_iam_role.this (modules/aws/iam/tfc-management-roles/main.tf#L393)
- resource.aws_iam_role_policy.apply (modules/aws/iam/tfc-management-roles/main.tf#L434)
- resource.aws_iam_role_policy.plan_guard (modules/aws/iam/tfc-management-roles/main.tf#L426)
- resource.aws_iam_role_policy.security_teardown (modules/aws/iam/tfc-management-roles/main.tf#L444)
- resource.aws_iam_role_policy_attachment.read_only (modules/aws/iam/tfc-management-roles/main.tf#L417)
- data source.aws_caller_identity.current (modules/aws/iam/tfc-management-roles/main.tf#L391)
- data source.aws_partition.current (modules/aws/iam/tfc-management-roles/main.tf#L389)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_tfc_organization"></a> [tfc\_organization](#input\_tfc\_organization) | Terraform Cloud organization of the trusted workspaces (matched literally in the trust sub). | `string` | n/a | yes |
| <a name="input_delegated_admin_account_ids"></a> [delegated\_admin\_account\_ids](#input\_delegated\_admin\_account\_ids) | Accounts the aws-security role may register as delegated administrators (organizations account-ARN resources): the security-tooling account in the SRA layout. Empty = NO account (registration fails closed); the aws-organization stage sets the security-tooling account. | `list(string)` | `[]` | no |
| <a name="input_enable_security_service_teardown"></a> [enable\_security\_service\_teardown](#input\_enable\_security\_service\_teardown) | Teardown gate: let the aws-security apply role switch org-wide detection OFF (Disable*AdminAccount, DisableAWSServiceAccess, DeregisterDelegatedAdministrator for the security services). Default false: a routine aws-security apply can enable and register, never disable. Set true only for a reviewed aws-security destroy (docs/runbooks/aws-teardown.md), then back to false. | `bool` | `false` | no |
| <a name="input_max_session_duration"></a> [max\_session\_duration](#input\_max\_session\_duration) | Maximum session duration in seconds (3600-43200). | `number` | `3600` | no |
| <a name="input_member_pivot_role_names"></a> [member\_pivot\_role\_names](#input\_member\_pivot\_role\_names) | Member-account role names the management roles must never assume (OrganizationAccountAccessRole and the member tfc-* roles by default). | `list(string)` | <pre>[<br/>  "OrganizationAccountAccessRole",<br/>  "tfc-plan",<br/>  "tfc-apply",<br/>  "break-glass"<br/>]</pre> | no |
| <a name="input_oidc_provider_arn"></a> [oidc\_provider\_arn](#input\_oidc\_provider\_arn) | ARN of the management account's TFC OIDC provider (created in phase 0). Null derives arn:<partition>:iam::<this account>:oidc-provider/<tfc\_hostname>. | `string` | `null` | no |
| <a name="input_protected_role_names"></a> [protected\_role\_names](#input\_protected\_role\_names) | Management-account role names, beyond <role\_name\_prefix>* (which already covers the phase-0 tfc-mgmt-plan / tfc-mgmt-apply roles), that no management role may modify. The break-glass role names are protected too: the aws-security management role may not create or edit the management break-glass role, which every member break-glass role trusts. | `list(string)` | <pre>[<br/>  "OrganizationAccountAccessRole",<br/>  "OrganizationBreakGlass",<br/>  "break-glass"<br/>]</pre> | no |
| <a name="input_role_name_prefix"></a> [role\_name\_prefix](#input\_role\_name\_prefix) | Prefix of the role names (<prefix><workspace>-<phase>). Every role with this prefix is protected from modification by the roles themselves. | `string` | `"tfc-mgmt-"` | no |
| <a name="input_security_owner_tag"></a> [security\_owner\_tag](#input\_security\_owner\_tag) | Tag that marks the management-account KMS keys the aws-security role owns. Its provider default\_tags set Workspace = aws-security on everything it creates. | <pre>object({<br/>    key   = string<br/>    value = string<br/>  })</pre> | <pre>{<br/>  "key": "Workspace",<br/>  "value": "aws-security"<br/>}</pre> | no |
| <a name="input_security_service_principals"></a> [security\_service\_principals](#input\_security\_service\_principals) | Service principals the aws-security role may register delegated admins / enable trusted access for. Anything else (member.org.stacksets.cloudformation.amazonaws.com, sso.amazonaws.com, ...) stays with aws-organization. | `list(string)` | <pre>[<br/>  "guardduty.amazonaws.com",<br/>  "malware-protection.guardduty.amazonaws.com",<br/>  "securityhub.amazonaws.com",<br/>  "macie.amazonaws.com",<br/>  "inspector2.amazonaws.com",<br/>  "detective.amazonaws.com",<br/>  "fms.amazonaws.com",<br/>  "access-analyzer.amazonaws.com",<br/>  "config.amazonaws.com",<br/>  "config-multiaccountsetup.amazonaws.com",<br/>  "securitylake.amazonaws.com",<br/>  "cloudtrail.amazonaws.com",<br/>  "backup.amazonaws.com",<br/>  "ssm.amazonaws.com",<br/>  "resource-explorer-2.amazonaws.com"<br/>]</pre> | no |
| <a name="input_security_trail_name"></a> [security\_trail\_name](#input\_security\_trail\_name) | Name of the organization CloudTrail trail the aws-security role manages (cloudtrail-org trail\_name). Its cloudtrail:* permissions are scoped to this trail ARN. | `string` | `"org-trail"` | no |
| <a name="input_security_trail_role_pattern"></a> [security\_trail\_role\_pattern](#input\_security\_trail\_role\_pattern) | Exact name of the organization trail's CloudWatch Logs delivery role (created by aws-organization). The aws-security apply role may only PASS it to cloudtrail.amazonaws.com; it has no IAM write permissions. | `string` | `"org-trail-cloudwatch-delivery"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the roles. | `map(string)` | `{}` | no |
| <a name="input_tfc_hostname"></a> [tfc\_hostname](#input\_tfc\_hostname) | HCP Terraform / TFE hostname issuing the workload-identity tokens. | `string` | `"app.terraform.io"` | no |
| <a name="input_tfc_project"></a> [tfc\_project](#input\_tfc\_project) | Default TFC project of the trusted workspaces (matched literally in the trust sub). Override per workspace with workspaces[*].project. | `string` | `"Default Project"` | no |
| <a name="input_workspaces"></a> [workspaces](#input\_workspaces) | Management-default workspaces that get their own plan/apply role pair, keyed by workspace name. aws-security and aws-backup have built-in least-privilege apply policies; any other workspace must set apply\_policy\_json. project overrides tfc\_project for that workspace. | <pre>map(object({<br/>    project           = optional(string)<br/>    apply_policy_json = optional(string)<br/>  }))</pre> | <pre>{<br/>  "aws-backup": {},<br/>  "aws-security": {}<br/>}</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_apply_policies"></a> [apply\_policies](#output\_apply\_policies) | Workspace name => rendered apply-role inline policy JSON (evidence and review). |
| <a name="output_apply_role_arns"></a> [apply\_role\_arns](#output\_apply\_role\_arns) | Workspace name => management-account APPLY role ARN (TFC\_AWS\_APPLY\_ROLE\_ARN). |
| <a name="output_plan_role_arns"></a> [plan\_role\_arns](#output\_plan\_role\_arns) | Workspace name => management-account PLAN role ARN (TFC\_AWS\_PLAN\_ROLE\_ARN). |
| <a name="output_security_teardown_policy"></a> [security\_teardown\_policy](#output\_security\_teardown\_policy) | Rendered aws-security teardown inline policy JSON, attached only while enable\_security\_service\_teardown is true (null otherwise). |
<!-- END_TF_DOCS -->
