# tfc-oidc-baseline

Deploys a Terraform Cloud **workload-identity baseline** into AWS member accounts
from the management (or CloudFormation delegated-admin) account, using a
`SERVICE_MANAGED` CloudFormation StackSet with auto-deployment — no Terraform
provider per account.

Each targeted member account receives:

| Resource | Purpose |
|---|---|
| `AWS::IAM::OIDCProvider` for `https://<tfc_hostname>` | Audience `aws.workload.identity`. |
| `tfc-plan` role (bound accounts only) | `ReadOnlyAccess`. Trusts `<host>:sub = organization:<org>:project:<project>:workspace:<ws>:run_phase:plan`. |
| `tfc-apply` role (bound accounts only) | `AdministratorAccess` by default, **capped by a permissions boundary**. Trusts `...:run_phase:apply`. |
| `tfc-apply-boundary` managed policy | Embedded permissions boundary (default on, `enable_apply_permissions_boundary`). |

**Apply permissions boundary.** The boundary allows everything except:

- leaving the organization;
- stopping or deleting CloudTrail, GuardDuty (detector, members and administrator association) and Config (recorder and delivery channel);
- disabling Security Hub (`securityhub:Disable*`, `BatchDisableStandards`), Macie or Inspector, or deleting an Access Analyzer;
- changing the `tfc-plan` and `tfc-apply` roles, the OIDC provider or the boundary itself;
- creating, modifying, deleting, tagging or passing the break-glass role (`break_glass_role_name`), OrganizationAccountAccessRole or `stacksets-exec-*` (`protected_role_names`);
- destroying, disabling or rewriting the policy of a KMS key tagged `protected = "true"`, or removing that tag;
- setting or removing `dp:*` data-perimeter tags;
- `iam:CreateUser`, `iam:CreateAccessKey` and `iam:CreateLoginProfile`.

Creating and updating detective controls is still allowed, so the security and
workload layers can apply normally. To use your own boundary, supply
`apply_permissions_boundary_arn`. The boundary is a guardrail, not a full
privilege-escalation barrier. The apply role can still create a new
unbounded role, so the org deny-tamper SCP remains the primary control.

**Plan-role data-read deny.** `tfc-plan` is denied data-plane reads that
`ReadOnlyAccess` grants (object/secret/parameter/item reads, `kms:Decrypt`,
`kms:GenerateDataKey*`, `ec2:GetPasswordData`, console output, Glue connection
reads, log events, query results, image pulls). Reads Terraform needs to refresh
resources stay allowed: `lambda:GetFunction*` (environment variables),
`ecs:DescribeTaskDefinition` (container environment) and
`ec2:DescribeInstanceAttribute` (user data). Keep secrets out of those fields
and reference Secrets Manager or SSM instead.

**Member break-glass role.** With `enable_member_break_glass_role = true`, a
sibling StackSet (`member_break_glass_stack_set_name`) deploys
`break_glass_role_name` to every account in `member_break_glass_target_ou_ids`.
The role trusts only `member_break_glass_trusted_principal_arns` (management
account), with MFA by default. This occupies the role name that the org
deny-tamper SCP exempts, so nobody else can create it in a member account.

The organization and project are always matched literally. Workspace names are
matched exactly (`StringEquals`) unless `allow_workspace_wildcards = true`, which
switches the sub condition to `StringLike`. A bare `*` workspace is always rejected.

Per-account scoping is compiled into one template as CloudFormation `Conditions`
on `AWS::AccountId`. An account in a targeted OU with no `account_bindings` entry
(including one that joins later through auto-deployment) gets only the inert OIDC
provider. Its roles appear once you bind it and re-apply.

Set the outputs on each workspace as TFC dynamic-credential variables:

```text
TFC_AWS_PROVIDER_AUTH  = true
TFC_AWS_PLAN_ROLE_ARN  = <plan_role_arns[account_key]>
TFC_AWS_APPLY_ROLE_ARN = <apply_role_arns[account_key]>
```

**Limits.**
- Service-managed StackSets never deploy to the management account. The management-account role used by `aws-organization` (and by the management-account default provider of `aws-security` / `aws-backup`) stays a phase-0, human-created role.
- Deploy to exactly one region (`stack_set_instance_region`), because IAM is global.
- The template must stay within CloudFormation's 51,200-byte inline limit, which is enforced by a precondition (about 30 bindings).
- The organization needs trusted access for `member.org.stacksets.cloudformation.amazonaws.com`.

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
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.54.0 |



## Resources

The following resources are created:


- resource.aws_cloudformation_stack_set.break_glass (modules/aws/iam/tfc-oidc-baseline/main.tf#L628)
- resource.aws_cloudformation_stack_set.this (modules/aws/iam/tfc-oidc-baseline/main.tf#L511)
- resource.aws_cloudformation_stack_set_instance.break_glass (modules/aws/iam/tfc-oidc-baseline/main.tf#L664)
- resource.aws_cloudformation_stack_set_instance.this (modules/aws/iam/tfc-oidc-baseline/main.tf#L551)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_tfc_organization"></a> [tfc\_organization](#input\_tfc\_organization) | Terraform Cloud organization name. Matched LITERALLY in every trust policy sub condition — wildcards are rejected so no other TFC organization can ever assume the roles. | `string` | n/a | yes |
| <a name="input_account_bindings"></a> [account\_bindings](#input\_account\_bindings) | Map of account key -> binding. Each binding names the member account (account\_id), the TFC workspaces allowed to assume its tfc-plan/tfc-apply roles, and an optional TFC project override. Workspace names are matched exactly unless allow\_workspace\_wildcards is true. Accounts in a targeted OU without a binding receive only the OIDC provider (no roles). | <pre>map(object({<br/>    account_id = string<br/>    workspaces = list(string)<br/>    project    = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_allow_workspace_wildcards"></a> [allow\_workspace\_wildcards](#input\_allow\_workspace\_wildcards) | Allow '*' inside workspace names in account\_bindings (e.g. aws-workload-*), switching the sub condition from StringEquals to StringLike. The organization and project are always matched literally. Default false: exact workspace names only. | `bool` | `false` | no |
| <a name="input_apply_boundary_policy_name"></a> [apply\_boundary\_policy\_name](#input\_apply\_boundary\_policy\_name) | Name of the embedded permissions-boundary managed policy created in each targeted account. | `string` | `"tfc-apply-boundary"` | no |
| <a name="input_apply_permissions_boundary_arn"></a> [apply\_permissions\_boundary\_arn](#input\_apply\_permissions\_boundary\_arn) | Optional existing permissions-boundary policy ARN to use instead of the embedded one. The policy must already exist in every bound account (an AWS-managed policy, or a same-named customer policy deployed by another StackSet). Null (default) = the embedded boundary. Ignored when enable\_apply\_permissions\_boundary = false. | `string` | `null` | no |
| <a name="input_apply_role_name"></a> [apply\_role\_name](#input\_apply\_role\_name) | Name of the role TFC assumes during the apply phase (TFC\_AWS\_APPLY\_ROLE\_ARN). | `string` | `"tfc-apply"` | no |
| <a name="input_apply_role_policy_arns"></a> [apply\_role\_policy\_arns](#input\_apply\_role\_policy\_arns) | Managed policy ARNs attached to the apply role. Defaults to AdministratorAccess (the apply role provisions arbitrary landing-zone resources), capped by the apply permissions boundary (enable\_apply\_permissions\_boundary); narrow it per organization if your layers allow. | `list(string)` | <pre>[<br/>  "arn:aws:iam::aws:policy/AdministratorAccess"<br/>]</pre> | no |
| <a name="input_break_glass_role_name"></a> [break\_glass\_role\_name](#input\_break\_glass\_role\_name) | Name (optionally path-prefixed, e.g. emergency/break-glass) of the break-glass role in MEMBER accounts — must match the org deny-tamper SCP's break-glass exemption. The tfc-apply boundary denies creating, modifying, deleting, tagging or passing it, and enable\_member\_break\_glass\_role deploys it. | `string` | `"break-glass"` | no |
| <a name="input_call_as"></a> [call\_as](#input\_call\_as) | Whether the StackSet is managed from the management account (SELF) or a CloudFormation delegated-administrator account (DELEGATED\_ADMIN). | `string` | `"SELF"` | no |
| <a name="input_create_github_oidc_provider"></a> [create\_github\_oidc\_provider](#input\_create\_github\_oidc\_provider) | Also create the account-wide GitHub Actions OIDC provider (https://token.actions.githubusercontent.com, aud sts.amazonaws.com) in every targeted account. The apply boundary denies the pipeline creating identity providers itself, so app-services GitHub deploy roles rely on this one. Default true. Pin which GitHub owners may use it with the organization RCP (github\_federation\_owners). | `bool` | `true` | no |
| <a name="input_enable_apply_boundary_propagation"></a> [enable\_apply\_boundary\_propagation](#input\_enable\_apply\_boundary\_propagation) | Make the embedded tfc-apply boundary self-propagating (default true): tfc-apply may only CreateRole / PutRolePermissionsBoundary / AttachRolePolicy / PutRolePolicy when the target role carries this same boundary (iam:PermissionsBoundary), and may never delete a permissions boundary. Without it the apply identity can create an unbounded role, attach AdministratorAccess and assume it. Every aws\_iam\_role created by tfc-apply in a member account must then set permissions\_boundary to arn:<partition>:iam::<account>:policy/<apply\_boundary\_policy\_name>. Applies to the embedded boundary only (apply\_permissions\_boundary\_arn = null). | `bool` | `true` | no |
| <a name="input_enable_apply_permissions_boundary"></a> [enable\_apply\_permissions\_boundary](#input\_enable\_apply\_permissions\_boundary) | Cap the apply role with a permissions boundary (default true). With apply\_permissions\_boundary\_arn = null the StackSet embeds a managed boundary that allows everything EXCEPT: leaving the org; stopping/deleting CloudTrail, GuardDuty and Config; disabling Security Hub, Macie, Inspector or Access Analyzer; modifying the plan/apply roles, the OIDC provider or the boundary itself; creating/modifying/passing the break-glass, OrganizationAccountAccessRole or StackSet execution roles; destroying or re-policying protected KMS keys; dp:* tag changes; and iam:CreateUser/CreateAccessKey/CreateLoginProfile. | `bool` | `true` | no |
| <a name="input_enable_member_break_glass_role"></a> [enable\_member\_break\_glass\_role](#input\_enable\_member\_break\_glass\_role) | Deploy the break-glass role (break\_glass\_role\_name) into every account of member\_break\_glass\_target\_ou\_ids via a sibling SERVICE\_MANAGED StackSet, so the SCP-exempt break-glass name is occupied (and protected) in each member account instead of being claimable by the first principal to create it. Default false at module level; the organization stage enables it for the org root. | `bool` | `false` | no |
| <a name="input_enable_plan_role_data_read_deny"></a> [enable\_plan\_role\_data\_read\_deny](#input\_enable\_plan\_role\_data\_read\_deny) | Attach an inline deny to the plan role for data-plane reads that ReadOnlyAccess otherwise grants (s3:GetObject*, secretsmanager:GetSecretValue / BatchGetSecretValue, ssm:GetParameter*, kms:Decrypt / GenerateDataKey*, ec2:GetPasswordData / console output, glue:GetConnection(s), DynamoDB item reads, sqs:ReceiveMessage, kinesis:GetRecords, CloudWatch Logs event reads/queries, rds-data, Athena/Redshift Data results, ECR image pulls). Default true: speculative PR plans run as this role, so it reads configuration, not data. | `bool` | `true` | no |
| <a name="input_kms_protection_tag_key"></a> [kms\_protection\_tag\_key](#input\_kms\_protection\_tag\_key) | Resource-tag key marking protected KMS keys (value "true"). The tfc-apply boundary denies ScheduleKeyDeletion / DisableKey / DisableKeyRotation / DeleteImportedKeyMaterial / PutKeyPolicy on such keys and removing or rewriting the tag. Must match the organization-policy kms\_protection\_tag\_key and the kms-key protection\_tag\_key. | `string` | `"protected"` | no |
| <a name="input_max_session_duration"></a> [max\_session\_duration](#input\_max\_session\_duration) | Maximum session duration (seconds) for both roles. TFC requests 1 hour by default. | `number` | `3600` | no |
| <a name="input_member_break_glass_mfa_max_age"></a> [member\_break\_glass\_mfa\_max\_age](#input\_member\_break\_glass\_mfa\_max\_age) | Maximum MFA age (seconds) accepted by the member break-glass trust when member\_break\_glass\_require\_mfa is true. | `number` | `3600` | no |
| <a name="input_member_break_glass_policy_arns"></a> [member\_break\_glass\_policy\_arns](#input\_member\_break\_glass\_policy\_arns) | Managed policy ARNs attached to the member break-glass role. | `list(string)` | <pre>[<br/>  "arn:aws:iam::aws:policy/AdministratorAccess"<br/>]</pre> | no |
| <a name="input_member_break_glass_require_mfa"></a> [member\_break\_glass\_require\_mfa](#input\_member\_break\_glass\_require\_mfa) | Require aws:MultiFactorAuthPresent (and aws:MultiFactorAuthAge < member\_break\_glass\_mfa\_max\_age) on the member break-glass trust. Default true. MFA context is carried by an IAM user's MFA-authenticated session; a role session obtained by role chaining may not carry it — validate the break-glass path end to end before relying on it. | `bool` | `true` | no |
| <a name="input_member_break_glass_stack_set_name"></a> [member\_break\_glass\_stack\_set\_name](#input\_member\_break\_glass\_stack\_set\_name) | Name of the SERVICE\_MANAGED StackSet that deploys the member break-glass role. | `string` | `"member-break-glass"` | no |
| <a name="input_member_break_glass_target_ou_ids"></a> [member\_break\_glass\_target\_ou\_ids](#input\_member\_break\_glass\_target\_ou\_ids) | Map of stable name -> OU or root ID the member break-glass StackSet deploys to (one stack instance each). Use the organization root to cover every member account (service-managed StackSets never deploy to the management account). | `map(string)` | `{}` | no |
| <a name="input_member_break_glass_trusted_principal_arns"></a> [member\_break\_glass\_trusted\_principal\_arns](#input\_member\_break\_glass\_trusted\_principal\_arns) | Account-qualified management-account principal ARNs (role or user) allowed to assume the member break-glass role. Required when enable\_member\_break\_glass\_role is true. | `list(string)` | `[]` | no |
| <a name="input_oidc_thumbprints"></a> [oidc\_thumbprints](#input\_oidc\_thumbprints) | Optional OIDC provider certificate thumbprints. AWS validates TFC's certificate against its trusted CA library, so the default (empty) omits ThumbprintList. | `list(string)` | `[]` | no |
| <a name="input_partition"></a> [partition](#input\_partition) | AWS partition used to build the role ARN outputs. | `string` | `"aws"` | no |
| <a name="input_plan_role_data_read_exempt_arns"></a> [plan\_role\_data\_read\_exempt\_arns](#input\_plan\_role\_data\_read\_exempt\_arns) | Resource ARNs (patterns allowed) excluded from the plan-role data-plane deny (rendered as NotResource). Use for Terraform-managed resources whose refresh reads data, e.g. an aws\_secretsmanager\_secret\_version or aws\_s3\_object the plan must diff. Empty (default) = deny on every resource. | `list(string)` | `[]` | no |
| <a name="input_plan_role_name"></a> [plan\_role\_name](#input\_plan\_role\_name) | Name of the read-only role TFC assumes during the plan phase (TFC\_AWS\_PLAN\_ROLE\_ARN). | `string` | `"tfc-plan"` | no |
| <a name="input_plan_role_policy_arns"></a> [plan\_role\_policy\_arns](#input\_plan\_role\_policy\_arns) | Managed policy ARNs attached to the plan role. Must be read-only: AdministratorAccess, PowerUserAccess and IAMFullAccess are rejected. | `list(string)` | <pre>[<br/>  "arn:aws:iam::aws:policy/ReadOnlyAccess"<br/>]</pre> | no |
| <a name="input_protected_role_names"></a> [protected\_role\_names](#input\_protected\_role\_names) | Further member-account role names or patterns the tfc-apply boundary forbids the apply identity to create, modify, delete, tag or pass (in addition to break\_glass\_role\_name and its own tfc-plan/tfc-apply roles). | `list(string)` | <pre>[<br/>  "OrganizationAccountAccessRole",<br/>  "stacksets-exec-*"<br/>]</pre> | no |
| <a name="input_stack_set_instance_region"></a> [stack\_set\_instance\_region](#input\_stack\_set\_instance\_region) | Single region the stack instances are deployed to. IAM is global, so the baseline must be deployed to exactly ONE region (a second region would collide on role names). null = the provider's region. | `string` | `null` | no |
| <a name="input_stack_set_name"></a> [stack\_set\_name](#input\_stack\_set\_name) | Name of the SERVICE\_MANAGED CloudFormation StackSet that deploys the baseline. | `string` | `"tfc-oidc-baseline"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the StackSet (propagated by CloudFormation to the IAM resources it creates). | `map(string)` | `{}` | no |
| <a name="input_target_ou_ids"></a> [target\_ou\_ids](#input\_target\_ou\_ids) | Map of stable OU name -> OU ID the StackSet deploys to (one stack instance per OU). Every account in these OUs (including accounts that join later, via auto-deployment) receives the OIDC provider; bound accounts also receive the roles. Service-managed StackSets never deploy to the management account. | `map(string)` | `{}` | no |
| <a name="input_tfc_hostname"></a> [tfc\_hostname](#input\_tfc\_hostname) | Hostname of the Terraform Cloud / Enterprise instance that issues the workload-identity tokens. Becomes the OIDC provider URL (https://<hostname>) and the prefix of the aud/sub condition keys. | `string` | `"app.terraform.io"` | no |
| <a name="input_tfc_project"></a> [tfc\_project](#input\_tfc\_project) | Default Terraform Cloud project the bound workspaces live in. Matched literally in the sub condition; override per binding with account\_bindings[*].project. | `string` | `"Default Project"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_apply_permissions_boundary"></a> [apply\_permissions\_boundary](#output\_apply\_permissions\_boundary) | Permissions boundary on the apply roles: "embedded:<policy-name>" for the StackSet-managed boundary, the supplied ARN, or null when disabled. |
| <a name="output_apply_role_arns"></a> [apply\_role\_arns](#output\_apply\_role\_arns) | Map of account key -> apply role ARN (set as TFC\_AWS\_APPLY\_ROLE\_ARN on the bound workspaces). |
| <a name="output_apply_role_name"></a> [apply\_role\_name](#output\_apply\_role\_name) | Name of the apply-phase role created in every bound account. |
| <a name="output_member_break_glass_stack_set_name"></a> [member\_break\_glass\_stack\_set\_name](#output\_member\_break\_glass\_stack\_set\_name) | Name of the member break-glass StackSet, or null when enable\_member\_break\_glass\_role is false. |
| <a name="output_member_break_glass_template_body"></a> [member\_break\_glass\_template\_body](#output\_member\_break\_glass\_template\_body) | The rendered CloudFormation template (JSON) of the member break-glass StackSet (rendered even when enable\_member\_break\_glass\_role is false). |
| <a name="output_oidc_provider_url"></a> [oidc\_provider\_url](#output\_oidc\_provider\_url) | Issuer URL of the IAM OIDC provider created in each targeted member account. |
| <a name="output_plan_role_arns"></a> [plan\_role\_arns](#output\_plan\_role\_arns) | Map of account key -> plan role ARN (set as TFC\_AWS\_PLAN\_ROLE\_ARN on the bound workspaces). |
| <a name="output_plan_role_name"></a> [plan\_role\_name](#output\_plan\_role\_name) | Name of the read-only plan-phase role created in every bound account. |
| <a name="output_stack_set_arn"></a> [stack\_set\_arn](#output\_stack\_set\_arn) | ARN of the StackSet. |
| <a name="output_stack_set_instance_ids"></a> [stack\_set\_instance\_ids](#output\_stack\_set\_instance\_ids) | Map of targeted OU name -> stack set instance ID. |
| <a name="output_stack_set_name"></a> [stack\_set\_name](#output\_stack\_set\_name) | Name of the SERVICE\_MANAGED StackSet that deploys the TFC OIDC baseline. |
| <a name="output_sub_condition_operator"></a> [sub\_condition\_operator](#output\_sub\_condition\_operator) | IAM condition operator used for the sub claim: StringEquals (exact, default) or StringLike (workspace wildcards enabled). |
| <a name="output_template_body"></a> [template\_body](#output\_template\_body) | The rendered CloudFormation template (JSON) deployed by the StackSet. |
| <a name="output_trust_subjects"></a> [trust\_subjects](#output\_trust\_subjects) | Map of account key -> { plan, apply } lists of the exact TFC sub claims each role trusts. |
<!-- END_TF_DOCS -->

## Examples

See [`examples/basic/`](examples/basic/main.tf).
