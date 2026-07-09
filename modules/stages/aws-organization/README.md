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
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |



## Modules


- account - ../../aws/account
- cost_governance - ../../aws/cost-governance
- organization - ../../aws/organization
- policies - ../../aws/organization-policy
- root_access - ../../aws/iam-organizations-features




## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_break_glass_role_arn"></a> [break\_glass\_role\_arn](#input\_break\_glass\_role\_arn) | Account-qualified exact ARN of the emergency break-glass role. Carved out of every guardrail deny statement. | `string` | n/a | yes |
| <a name="input_log_archive_bucket_name"></a> [log\_archive\_bucket\_name](#input\_log\_archive\_bucket\_name) | Name of the central log-archive S3 bucket protected from Object Lock / governance-retention tampering by the deny-tamper SCP. | `string` | n/a | yes |
| <a name="input_terraform_run_role_arn"></a> [terraform\_run\_role\_arn](#input\_terraform\_run\_role\_arn) | Account-qualified exact ARN of the Terraform Cloud run role. Carved out of every guardrail deny statement so automation is not locked out. | `string` | n/a | yes |
| <a name="input_accounts"></a> [accounts](#input\_accounts) | Foundational member accounts to create, keyed by account name. Each entry sets the root email, the target OU name (must exist in the organization OU tree), optional alternate contacts, and optional tags. Defaults to the six SRA foundational accounts with placeholder emails the root is expected to override. | <pre>map(object({<br/>    email = string<br/>    ou    = string<br/>    alternate_contacts = optional(map(object({<br/>      contact_type  = string<br/>      name          = string<br/>      title         = string<br/>      email_address = string<br/>      phone_number  = string<br/>    })), {})<br/>    tags = optional(map(string), {})<br/>  }))</pre> | <pre>{<br/>  "backup": {<br/>    "email": "aws+backup@example.com",<br/>    "ou": "Infrastructure"<br/>  },<br/>  "forensics": {<br/>    "email": "aws+forensics@example.com",<br/>    "ou": "Security"<br/>  },<br/>  "log_archive": {<br/>    "email": "aws+log-archive@example.com",<br/>    "ou": "Security"<br/>  },<br/>  "network": {<br/>    "email": "aws+network@example.com",<br/>    "ou": "Infrastructure"<br/>  },<br/>  "security_tooling": {<br/>    "email": "aws+security-tooling@example.com",<br/>    "ou": "Security"<br/>  },<br/>  "shared_services": {<br/>    "email": "aws+shared-services@example.com",<br/>    "ou": "Infrastructure"<br/>  }<br/>}</pre> | no |
| <a name="input_allowed_regions"></a> [allowed\_regions](#input\_allowed\_regions) | Regions permitted by the region-restriction SCP. Requests to any other region are denied (global services are carved out). | `list(string)` | <pre>[<br/>  "eu-west-2"<br/>]</pre> | no |
| <a name="input_budgets"></a> [budgets](#input\_budgets) | Monthly COST budgets keyed by budget name, passed to the cost-governance module. limit\_amount is the USD limit; threshold\_percent triggers an ACTUAL-spend notification; emails receive the notification. | <pre>map(object({<br/>    limit_amount      = string<br/>    threshold_percent = number<br/>    emails            = optional(list(string), [])<br/>  }))</pre> | <pre>{<br/>  "org-monthly": {<br/>    "limit_amount": "1000",<br/>    "threshold_percent": 80<br/>  }<br/>}</pre> | no |
| <a name="input_cost_allocation_tags"></a> [cost\_allocation\_tags](#input\_cost\_allocation\_tags) | Tag keys to activate as cost-allocation tags in Cost Explorer / the Cost & Usage Report. Should mirror the tag-policy keys. | `list(string)` | <pre>[<br/>  "CostCenter",<br/>  "Environment",<br/>  "Owner"<br/>]</pre> | no |
| <a name="input_cost_anomaly_email"></a> [cost\_anomaly\_email](#input\_cost\_anomaly\_email) | Email address that receives Cost Anomaly Detection alerts. | `string` | `"finops@example.com"` | no |
| <a name="input_cost_notifications_topic_arn"></a> [cost\_notifications\_topic\_arn](#input\_cost\_notifications\_topic\_arn) | Optional SNS topic ARN that budget notifications are published to, in addition to per-budget email subscribers. Empty string disables SNS fan-out. | `string` | `""` | no |
| <a name="input_enable_cost_governance"></a> [enable\_cost\_governance](#input\_enable\_cost\_governance) | Gate for the cost-governance module (budgets, Cost Anomaly Detection, cost-allocation tags). When false the module composes as a no-op. | `bool` | `true` | no |
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
<!-- END_TF_DOCS -->
