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



## Modules


- account - ../../governance/account
- cost_governance - ../../governance/cost-governance
- organization - ../../governance/organization
- policies - ../../governance/organization-policy
- root_access - ../../governance/iam-organizations-features
- tfc_oidc_baseline - ../../iam/tfc-oidc-baseline




## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_break_glass_role_arn"></a> [break\_glass\_role\_arn](#input\_break\_glass\_role\_arn) | Account-qualified exact ARN of the emergency break-glass role. Carved out of every guardrail deny statement. | `string` | n/a | yes |
| <a name="input_log_archive_bucket_name"></a> [log\_archive\_bucket\_name](#input\_log\_archive\_bucket\_name) | Name of the central log-archive S3 bucket protected from Object Lock / governance-retention tampering by the deny-tamper SCP. | `string` | n/a | yes |
| <a name="input_terraform_run_role_arn"></a> [terraform\_run\_role\_arn](#input\_terraform\_run\_role\_arn) | Account-qualified exact ARN of the Terraform Cloud run role. Carved out of every guardrail deny statement so automation is not locked out. | `string` | n/a | yes |
| <a name="input_accounts"></a> [accounts](#input\_accounts) | Foundational member accounts to create, keyed by account name. Each entry sets the root email, the target OU name (must exist in the organization OU tree), optional alternate contacts, and optional tags. Defaults to the six SRA foundational accounts with placeholder emails the root is expected to override. | <pre>map(object({<br/>    email = string<br/>    ou    = string<br/>    alternate_contacts = optional(map(object({<br/>      contact_type  = string<br/>      name          = string<br/>      title         = string<br/>      email_address = string<br/>      phone_number  = string<br/>    })), {})<br/>    tags = optional(map(string), {})<br/>  }))</pre> | <pre>{<br/>  "backup": {<br/>    "email": "aws+backup@example.com",<br/>    "ou": "Infrastructure"<br/>  },<br/>  "forensics": {<br/>    "email": "aws+forensics@example.com",<br/>    "ou": "Security"<br/>  },<br/>  "log_archive": {<br/>    "email": "aws+log-archive@example.com",<br/>    "ou": "Security"<br/>  },<br/>  "network": {<br/>    "email": "aws+network@example.com",<br/>    "ou": "Infrastructure"<br/>  },<br/>  "security_tooling": {<br/>    "email": "aws+security-tooling@example.com",<br/>    "ou": "Security"<br/>  },<br/>  "shared_services": {<br/>    "email": "aws+shared-services@example.com",<br/>    "ou": "Infrastructure"<br/>  }<br/>}</pre> | no |
| <a name="input_allow_vpc_bpa_exclusions"></a> [allow\_vpc\_bpa\_exclusions](#input\_allow\_vpc\_bpa\_exclusions) | Whether member accounts may create VPC Block Public Access exclusions under the declarative EC2 policy. Default false. | `bool` | `false` | no |
| <a name="input_allowed_regions"></a> [allowed\_regions](#input\_allowed\_regions) | Regions permitted by the region-restriction SCP. Requests to any other region are denied (global services are carved out). | `list(string)` | <pre>[<br/>  "eu-west-2"<br/>]</pre> | no |
| <a name="input_break_glass_role_names"></a> [break\_glass\_role\_names](#input\_break\_glass\_role\_names) | Member-account break-glass role names for the deny-tamper SCP (sole exemption from the destructive statements). Empty (default) derives the name from break\_glass\_role\_arn. | `list(string)` | `[]` | no |
| <a name="input_budgets"></a> [budgets](#input\_budgets) | Monthly COST budgets keyed by budget name, passed to the cost-governance module. limit\_amount is the USD limit; threshold\_percent triggers an ACTUAL-spend notification; emails receive the notification. | <pre>map(object({<br/>    limit_amount      = string<br/>    threshold_percent = number<br/>    emails            = optional(list(string), [])<br/>  }))</pre> | <pre>{<br/>  "org-monthly": {<br/>    "limit_amount": "1000",<br/>    "threshold_percent": 80<br/>  }<br/>}</pre> | no |
| <a name="input_cost_allocation_tags"></a> [cost\_allocation\_tags](#input\_cost\_allocation\_tags) | Tag keys to activate as cost-allocation tags in Cost Explorer / the Cost & Usage Report. Should mirror the tag-policy keys. | `list(string)` | <pre>[<br/>  "CostCenter",<br/>  "Environment",<br/>  "Owner"<br/>]</pre> | no |
| <a name="input_cost_anomaly_email"></a> [cost\_anomaly\_email](#input\_cost\_anomaly\_email) | Email address that receives Cost Anomaly Detection alerts. | `string` | `"finops@example.com"` | no |
| <a name="input_cost_notifications_topic_arn"></a> [cost\_notifications\_topic\_arn](#input\_cost\_notifications\_topic\_arn) | Optional SNS topic ARN that budget notifications are published to, in addition to per-budget email subscribers. Empty string disables SNS fan-out. | `string` | `""` | no |
| <a name="input_data_perimeter_trusted_account_ids"></a> [data\_perimeter\_trusted\_account\_ids](#input\_data\_perimeter\_trusted\_account\_ids) | Optional 12-digit account IDs outside the organization trusted by the RCP data perimeter (aws:PrincipalAccount / aws:SourceAccount). Empty (default) trusts only the organization. | `list(string)` | `[]` | no |
| <a name="input_enable_cost_governance"></a> [enable\_cost\_governance](#input\_enable\_cost\_governance) | Gate for the cost-governance module (budgets, Cost Anomaly Detection, cost-allocation tags). When false the module composes as a no-op. | `bool` | `true` | no |
| <a name="input_enable_tfc_oidc_baseline"></a> [enable\_tfc\_oidc\_baseline](#input\_enable\_tfc\_oidc\_baseline) | Gate for the TFC OIDC baseline StackSet (OIDC provider + tfc-plan/tfc-apply roles in member accounts). Requires tfc\_organization when true. | `bool` | `true` | no |
| <a name="input_pipeline_role_names"></a> [pipeline\_role\_names](#input\_pipeline\_role\_names) | Member-account Terraform pipeline role names (or name patterns) passed to the deny-tamper SCP. Rendered as arn:aws:iam::*:role/<name>: exempt from the security-service reconfiguration denies and protected from IAM modification. SCPs never apply to the management account, so these must be the roles that run IN member accounts. | `list(string)` | <pre>[<br/>  "tfc-apply",<br/>  "OrganizationAccountAccessRole",<br/>  "stacksets-exec-*"<br/>]</pre> | no |
| <a name="input_tfc_apply_permissions_boundary_arn"></a> [tfc\_apply\_permissions\_boundary\_arn](#input\_tfc\_apply\_permissions\_boundary\_arn) | Optional existing permissions-boundary policy ARN for the tfc-apply roles (must exist in every bound account). Null (default) = the embedded tfc-apply-boundary. | `string` | `null` | no |
| <a name="input_tfc_apply_role_policy_arns"></a> [tfc\_apply\_role\_policy\_arns](#input\_tfc\_apply\_role\_policy\_arns) | Managed policy ARNs attached to every member-account tfc-apply role (capped by the apply permissions boundary, tfc\_enable\_apply\_permissions\_boundary). | `list(string)` | <pre>[<br/>  "arn:aws:iam::aws:policy/AdministratorAccess"<br/>]</pre> | no |
| <a name="input_tfc_enable_apply_boundary_propagation"></a> [tfc\_enable\_apply\_boundary\_propagation](#input\_tfc\_enable\_apply\_boundary\_propagation) | Make the embedded tfc-apply boundary self-propagating (default true): tfc-apply can only create / grant to roles carrying the same boundary and can never remove a boundary, closing the create-unbounded-role escape. Every aws\_iam\_role created by tfc-apply in a member account must then set permissions\_boundary to the tfc-apply-boundary ARN. | `bool` | `true` | no |
| <a name="input_tfc_enable_apply_permissions_boundary"></a> [tfc\_enable\_apply\_permissions\_boundary](#input\_tfc\_enable\_apply\_permissions\_boundary) | Cap every member-account tfc-apply role with a permissions boundary (default true). With tfc\_apply\_permissions\_boundary\_arn = null the StackSet embeds tfc-apply-boundary: allow-all except leaving the org, stopping/deleting CloudTrail/GuardDuty/Config, modifying the TFC roles/OIDC provider/boundary, creating IAM users/access keys, and (tfc\_enable\_apply\_boundary\_propagation) creating or granting to roles without the same boundary. | `bool` | `true` | no |
| <a name="input_tfc_enable_plan_role_data_read_deny"></a> [tfc\_enable\_plan\_role\_data\_read\_deny](#input\_tfc\_enable\_plan\_role\_data\_read\_deny) | Attach an inline deny on data-plane reads (s3:GetObject*, secretsmanager:GetSecretValue, ssm:GetParameter*, kms:Decrypt, DynamoDB/SQS/Kinesis/Logs reads, ...) to every member-account tfc-plan role (default true). | `bool` | `true` | no |
| <a name="input_tfc_hostname"></a> [tfc\_hostname](#input\_tfc\_hostname) | Terraform Cloud / Enterprise hostname issuing the workload-identity tokens. | `string` | `"app.terraform.io"` | no |
| <a name="input_tfc_oidc_allow_workspace_wildcards"></a> [tfc\_oidc\_allow\_workspace\_wildcards](#input\_tfc\_oidc\_allow\_workspace\_wildcards) | Allow '*' inside bound workspace names (StringLike sub match). The organization and project are always literal. Default false: exact workspace names. | `bool` | `false` | no |
| <a name="input_tfc_oidc_call_as"></a> [tfc\_oidc\_call\_as](#input\_tfc\_oidc\_call\_as) | Manage the StackSet as the management account (SELF) or a CloudFormation delegated administrator (DELEGATED\_ADMIN). | `string` | `"SELF"` | no |
| <a name="input_tfc_organization"></a> [tfc\_organization](#input\_tfc\_organization) | Terraform Cloud organization whose workspaces the member-account roles trust (matched literally, never wildcarded). Required when enable\_tfc\_oidc\_baseline is true. | `string` | `null` | no |
| <a name="input_tfc_plan_role_data_read_exempt_arns"></a> [tfc\_plan\_role\_data\_read\_exempt\_arns](#input\_tfc\_plan\_role\_data\_read\_exempt\_arns) | Resource ARNs excluded from the tfc-plan data-plane deny (NotResource), for Terraform-managed resources whose refresh reads data (e.g. the aws-workload SaaS bridge secret). Empty (default) = deny everywhere. | `list(string)` | `[]` | no |
| <a name="input_tfc_project"></a> [tfc\_project](#input\_tfc\_project) | Default TFC project of the bound workspaces (matched literally in the trust sub). Override per account with tfc\_workspace\_bindings[*].project. | `string` | `"Default Project"` | no |
| <a name="input_tfc_workspace_bindings"></a> [tfc\_workspace\_bindings](#input\_tfc\_workspace\_bindings) | Map of account key (from accounts / workload\_accounts) -> TFC workspaces allowed to assume that account's tfc-plan / tfc-apply roles, with an optional project override. Add one entry per workload account, e.g. workload\_dev = { workspaces = ["aws-workload-dev"] }. The multi-account aws-security root is bound into security\_tooling, log\_archive and forensics; aws-backup into backup. | <pre>map(object({<br/>    workspaces = list(string)<br/>    project    = optional(string)<br/>  }))</pre> | <pre>{<br/>  "backup": {<br/>    "workspaces": [<br/>      "aws-backup"<br/>    ]<br/>  },<br/>  "forensics": {<br/>    "workspaces": [<br/>      "aws-security"<br/>    ]<br/>  },<br/>  "log_archive": {<br/>    "workspaces": [<br/>      "aws-security"<br/>    ]<br/>  },<br/>  "network": {<br/>    "workspaces": [<br/>      "aws-network"<br/>    ]<br/>  },<br/>  "security_tooling": {<br/>    "workspaces": [<br/>      "aws-security"<br/>    ]<br/>  },<br/>  "shared_services": {<br/>    "workspaces": [<br/>      "aws-identity",<br/>      "aws-shared-services"<br/>    ]<br/>  }<br/>}</pre> | no |
| <a name="input_workload_accounts"></a> [workload\_accounts](#input\_workload\_accounts) | Additional workload member accounts to create, keyed by account name. Merged with var.accounts; same object shape. | <pre>map(object({<br/>    email = string<br/>    ou    = string<br/>    alternate_contacts = optional(map(object({<br/>      contact_type  = string<br/>      name          = string<br/>      title         = string<br/>      email_address = string<br/>      phone_number  = string<br/>    })), {})<br/>    tags = optional(map(string), {})<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_account_ids"></a> [account\_ids](#output\_account\_ids) | Map of member-account name to account ID. |
| <a name="output_account_role_arns"></a> [account\_role\_arns](#output\_account\_role\_arns) | Map of member-account name to its cross-account access role ARN. |
| <a name="output_cost_budget_ids"></a> [cost\_budget\_ids](#output\_cost\_budget\_ids) | Map of budget name to budget resource ID created by the cost-governance module. Empty when cost governance is disabled. |
| <a name="output_management_account_id"></a> [management\_account\_id](#output\_management\_account\_id) | The account ID of the organization management (payer) account. |
| <a name="output_organization_id"></a> [organization\_id](#output\_organization\_id) | The ID of the AWS organization. |
| <a name="output_organization_root_id"></a> [organization\_root\_id](#output\_organization\_root\_id) | The ID of the organization root (r-xxxx), under which the top-level OUs are created. Consumed by the aws-security root as the Security Hub configuration-policy association target. |
| <a name="output_ou_ids"></a> [ou\_ids](#output\_ou\_ids) | Map of OU name (or parent/name path for child OUs) to OU ID. |
| <a name="output_policy_attachment_ids"></a> [policy\_attachment\_ids](#output\_policy\_attachment\_ids) | Map of guardrail attachment key to the attachment resource ID. |
| <a name="output_tfc_apply_role_arns"></a> [tfc\_apply\_role\_arns](#output\_tfc\_apply\_role\_arns) | Map of account key -> member-account tfc-apply role ARN. Set as TFC\_AWS\_APPLY\_ROLE\_ARN on the workspaces bound to that account. Empty when the TFC OIDC baseline is disabled. |
| <a name="output_tfc_oidc_stack_set_name"></a> [tfc\_oidc\_stack\_set\_name](#output\_tfc\_oidc\_stack\_set\_name) | Name of the StackSet deploying the TFC OIDC baseline, or null when disabled. |
| <a name="output_tfc_plan_role_arns"></a> [tfc\_plan\_role\_arns](#output\_tfc\_plan\_role\_arns) | Map of account key -> member-account tfc-plan (read-only) role ARN. Set as TFC\_AWS\_PLAN\_ROLE\_ARN on the workspaces bound to that account. Empty when the TFC OIDC baseline is disabled. |
| <a name="output_tfc_workspace_bindings"></a> [tfc\_workspace\_bindings](#output\_tfc\_workspace\_bindings) | Map of account key -> TFC workspace names bound to that account's tfc-plan / tfc-apply roles (empty when the baseline is disabled). |
<!-- END_TF_DOCS -->
