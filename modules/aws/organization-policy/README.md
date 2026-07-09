# organization-policy

AWS Organizations guardrail policies for the SRA landing zone. Renders a set of
organization policies from templated JSON files and attaches them to OU/account
targets. Covers all five policy types: three SCPs (deny-tamper,
region-restriction, baseline), a two-statement data-perimeter RCP (org-identity
+ confused-deputy + secure-transport), an `@@assign` declarative EC2 policy
(IMDSv2 + public-access blocks), a tag policy, and a daily backup policy.

`FullAWSAccess` / `RCPFullAWSAccess` are AWS-managed and never managed here.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	break_glass_role_arn = 
	log_archive_bucket_name = 
	management_account_id = 
	org_id = 
	security_account_id = 
	terraform_run_role_arn = 
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.54.0 |



## Resources

The following resources are created:


- resource.aws_organizations_policy.policy (modules/aws/organization-policy/main.tf#L68)
- resource.aws_organizations_policy_attachment.attach (modules/aws/organization-policy/main.tf#L75)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_break_glass_role_arn"></a> [break\_glass\_role\_arn](#input\_break\_glass\_role\_arn) | Account-qualified exact ARN of the emergency break-glass role. Carved out of every deny statement. | `string` | n/a | yes |
| <a name="input_log_archive_bucket_name"></a> [log\_archive\_bucket\_name](#input\_log\_archive\_bucket\_name) | Name of the central log-archive S3 bucket protected from Object Lock / governance-retention tampering by the deny-tamper SCP. | `string` | n/a | yes |
| <a name="input_management_account_id"></a> [management\_account\_id](#input\_management\_account\_id) | The organization management (payer) account ID. | `string` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | AWS Organizations organization ID (o-xxxxxxxxxx). Used as the org-identity anchor in the RCP data-perimeter policy. | `string` | n/a | yes |
| <a name="input_security_account_id"></a> [security\_account\_id](#input\_security\_account\_id) | The delegated-administrator security account ID. | `string` | n/a | yes |
| <a name="input_terraform_run_role_arn"></a> [terraform\_run\_role\_arn](#input\_terraform\_run\_role\_arn) | Account-qualified exact ARN of the Terraform Cloud run role. Carved out of every deny statement so automation is not locked out. | `string` | n/a | yes |
| <a name="input_allowed_regions"></a> [allowed\_regions](#input\_allowed\_regions) | Regions permitted by the region-restriction SCP. Requests to any other region are denied (global services are carved out). | `list(string)` | <pre>[<br/>  "eu-west-2",<br/>  "eu-west-1"<br/>]</pre> | no |
| <a name="input_attachments"></a> [attachments](#input\_attachments) | Policy attachments binding a policy\_key (name in the effective policy set) to a target OU root/OU/account ID. | <pre>list(object({<br/>    policy_key = string<br/>    target_id  = string<br/>  }))</pre> | `[]` | no |
| <a name="input_default_region"></a> [default\_region](#input\_default\_region) | Region used by the backup policy's default plan. | `string` | `"eu-west-2"` | no |
| <a name="input_policies"></a> [policies](#input\_policies) | Override map of policies to create, keyed by policy name. When empty (default), the module computes the built-in guardrail set from the templated JSON files. Content is a raw Organizations policy JSON string. | <pre>map(object({<br/>    type    = string<br/>    content = string<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_attachment_ids"></a> [attachment\_ids](#output\_attachment\_ids) | Map of "policy\_key:target\_id" to the attachment resource ID. |
| <a name="output_policy_arns"></a> [policy\_arns](#output\_policy\_arns) | Map of policy name to created Organizations policy ARN. |
| <a name="output_policy_ids"></a> [policy\_ids](#output\_policy\_ids) | Map of policy name to created Organizations policy ID. |
| <a name="output_policy_types"></a> [policy\_types](#output\_policy\_types) | Map of policy name to its Organizations policy type. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "organization_policy" {
  source = "../../modules/aws/organization-policy"

  org_id                  = "o-abc1234567"
  management_account_id   = "111111111111"
  security_account_id     = "222222222222"
  terraform_run_role_arn  = "arn:aws:iam::111111111111:role/tfc-run-role"
  break_glass_role_arn    = "arn:aws:iam::111111111111:role/break-glass"
  log_archive_bucket_name = "sra-log-archive-111111111111"

  # Attach guardrails to OU/account targets.
  attachments = [
    { policy_key = "scp-baseline", target_id = "r-abcd" },
    { policy_key = "rcp-data-perimeter", target_id = "ou-abcd-11111111" },
  ]
}
```

The built-in guardrail set is computed from the templated JSON in `policies/`.
Override the entire set by passing a non-empty `policies` map.

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
