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
- stopping or deleting CloudTrail, GuardDuty (detector and administrator association) and Config (recorder and delivery channel);
- changing the `tfc-plan` and `tfc-apply` roles, the OIDC provider or the boundary itself;
- `iam:CreateUser`, `iam:CreateAccessKey` and `iam:CreateLoginProfile`.

Creating and updating detective controls is still allowed, so the security and
workload layers can apply normally. To use your own boundary, supply
`apply_permissions_boundary_arn`. The boundary is a guardrail, not a full
privilege-escalation barrier. The apply role can still create a new
unbounded role, so the org deny-tamper SCP remains the primary control.

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


- resource.aws_cloudformation_stack_set.this (modules/aws/iam/tfc-oidc-baseline/main.tf#L255)
- resource.aws_cloudformation_stack_set_instance.this (modules/aws/iam/tfc-oidc-baseline/main.tf#L295)


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
| <a name="input_call_as"></a> [call\_as](#input\_call\_as) | Whether the StackSet is managed from the management account (SELF) or a CloudFormation delegated-administrator account (DELEGATED\_ADMIN). | `string` | `"SELF"` | no |
| <a name="input_enable_apply_permissions_boundary"></a> [enable\_apply\_permissions\_boundary](#input\_enable\_apply\_permissions\_boundary) | Cap the apply role with a permissions boundary (default true). With apply\_permissions\_boundary\_arn = null the StackSet embeds a managed boundary that allows everything EXCEPT: leaving the org; stopping/deleting CloudTrail, GuardDuty and Config; modifying the plan/apply roles, the OIDC provider or the boundary itself; and iam:CreateUser/CreateAccessKey/CreateLoginProfile. | `bool` | `true` | no |
| <a name="input_max_session_duration"></a> [max\_session\_duration](#input\_max\_session\_duration) | Maximum session duration (seconds) for both roles. TFC requests 1 hour by default. | `number` | `3600` | no |
| <a name="input_oidc_thumbprints"></a> [oidc\_thumbprints](#input\_oidc\_thumbprints) | Optional OIDC provider certificate thumbprints. AWS validates TFC's certificate against its trusted CA library, so the default (empty) omits ThumbprintList. | `list(string)` | `[]` | no |
| <a name="input_partition"></a> [partition](#input\_partition) | AWS partition used to build the role ARN outputs. | `string` | `"aws"` | no |
| <a name="input_plan_role_name"></a> [plan\_role\_name](#input\_plan\_role\_name) | Name of the read-only role TFC assumes during the plan phase (TFC\_AWS\_PLAN\_ROLE\_ARN). | `string` | `"tfc-plan"` | no |
| <a name="input_plan_role_policy_arns"></a> [plan\_role\_policy\_arns](#input\_plan\_role\_policy\_arns) | Managed policy ARNs attached to the plan role. Must be read-only: AdministratorAccess, PowerUserAccess and IAMFullAccess are rejected. | `list(string)` | <pre>[<br/>  "arn:aws:iam::aws:policy/ReadOnlyAccess"<br/>]</pre> | no |
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
