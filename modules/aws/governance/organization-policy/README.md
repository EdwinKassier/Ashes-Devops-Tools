# organization-policy

AWS Organizations guardrail policies for the SRA landing zone. Renders a set of
organization policies from templated JSON files and attaches them to OU/account
targets. Covers all five policy types: three SCPs (deny-tamper,
region-restriction, baseline), a two-statement data-perimeter RCP
(org-identity, confused-deputy, and secure-transport), an `@@assign`
declarative EC2 policy (IMDSv2 and public-access blocks), a tag policy, and a
daily backup policy.

`FullAWSAccess` / `RCPFullAWSAccess` are AWS-managed and never managed here.

## Data-perimeter RCP

Follows the AWS `data-perimeter-policy-examples` RCPs. `EnforceOrgIdentities`
lists explicit STS actions instead of `sts:*`, deliberately excluding
`AssumeRoleWithWebIdentity` / `AssumeRoleWithSAML` so OIDC/SAML federation
(e.g. Terraform Cloud dynamic credentials) keeps working. `ConfusedDeputyProtection`
carries the `Null aws:SourceAccount = false` guard so service-principal calls
without source context (EC2 instance profiles, Lambda/ECS task roles) are not
denied. Resources can opt out with the `dp:exclude:identity` / `dp:exclude:source`
= `"true"` tags; trusted external accounts go in
`data_perimeter_trusted_account_ids`. Validate in a sandbox org before attaching
at the root.

### Deny-tamper SCP

SCPs never apply to the management account, so carve-outs are member-account
role-name patterns (`arn:aws:iam::*:role/<name>`), not account-qualified ARNs:

- **Break-glass only** (`break_glass_role_names`, default derived from
  `break_glass_role_arn`): leave org, stop/delete CloudTrail, delete GuardDuty
  detector/members, disable Security Hub / Macie / Inspector, delete Access
  Analyzer, delete/disable/untag KMS keys tagged `protected = "true"`.
- **Pipeline roles + break-glass** (`pipeline_role_names`, default
  `["tfc-apply", "OrganizationAccountAccessRole"]`): CloudTrail selectors/trail
  updates, GuardDuty filters/detector updates, Security Hub standards disablement,
  Config recorder/delivery-channel changes (workload Config recorders are
  Terraform-managed in member accounts), flow-log deletion, Object Lock changes
  on the log archive, and protected KMS key-policy changes.
- The pipeline roles, OAAR and break-glass are protected from IAM modification
  by anyone else.

The rendered SCP is minified and tested to stay under the 5,120-character quota.
A role with the break-glass name must exist in member accounts for break-glass
to work there.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	break_glass_role_arn =
	log_archive_bucket_name =
	org_id =
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
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.54.0 |



## Resources

The following resources are created:


- resource.aws_organizations_policy.policy (modules/aws/governance/organization-policy/main.tf#L111)
- resource.aws_organizations_policy_attachment.attach (modules/aws/governance/organization-policy/main.tf#L118)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_break_glass_role_arn"></a> [break\_glass\_role\_arn](#input\_break\_glass\_role\_arn) | Account-qualified exact ARN of the emergency break-glass role. Carved out of every deny statement. | `string` | n/a | yes |
| <a name="input_log_archive_bucket_name"></a> [log\_archive\_bucket\_name](#input\_log\_archive\_bucket\_name) | Name of the central log-archive S3 bucket protected from Object Lock / governance-retention tampering by the deny-tamper SCP. | `string` | n/a | yes |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | AWS Organizations organization ID (o-xxxxxxxxxx). Used as the org-identity anchor in the RCP data-perimeter policy. | `string` | n/a | yes |
| <a name="input_terraform_run_role_arn"></a> [terraform\_run\_role\_arn](#input\_terraform\_run\_role\_arn) | Account-qualified exact ARN of the Terraform Cloud run role. Carved out of every deny statement so automation is not locked out. | `string` | n/a | yes |
| <a name="input_allow_vpc_bpa_exclusions"></a> [allow\_vpc\_bpa\_exclusions](#input\_allow\_vpc\_bpa\_exclusions) | Whether member accounts may create VPC Block Public Access exclusions under the declarative EC2 policy. Default false (exclusions\_allowed = disabled) so a member-account admin cannot exempt a VPC from the org-wide internet-gateway ingress block. | `bool` | `false` | no |
| <a name="input_allowed_regions"></a> [allowed\_regions](#input\_allowed\_regions) | Regions permitted by the region-restriction SCP. Requests to any other region are denied (global services are carved out). | `list(string)` | <pre>[<br/>  "eu-west-2",<br/>  "eu-west-1"<br/>]</pre> | no |
| <a name="input_attachments"></a> [attachments](#input\_attachments) | Policy attachments binding a policy\_key (name in the effective policy set) to a target OU root/OU/account ID. Keyed by a stable caller-chosen string so for\_each stays known at plan time even when target\_id is a computed root/OU ID. | <pre>map(object({<br/>    policy_key = string<br/>    target_id  = string<br/>  }))</pre> | `{}` | no |
| <a name="input_break_glass_role_names"></a> [break\_glass\_role\_names](#input\_break\_glass\_role\_names) | Names of the break-glass role as it exists in MEMBER accounts. Rendered as arn:aws:iam::*:role/<name> and the sole exemption from the destructive deny-tamper statements. Empty (default) derives the name from break\_glass\_role\_arn — a role with that name must then exist in each member account for break-glass to work there. | `list(string)` | `[]` | no |
| <a name="input_data_perimeter_trusted_account_ids"></a> [data\_perimeter\_trusted\_account\_ids](#input\_data\_perimeter\_trusted\_account\_ids) | Optional 12-digit account IDs OUTSIDE the organization that are trusted by the RCP data perimeter: their principals (aws:PrincipalAccount) may access org resources, and AWS service calls on their behalf (aws:SourceAccount) pass the confused-deputy check. Empty (default) trusts only the organization. Individual resources can also opt out with the dp:exclude:identity / dp:exclude:source = "true" resource tags. | `list(string)` | `[]` | no |
| <a name="input_default_region"></a> [default\_region](#input\_default\_region) | Region used by the backup policy's default plan. | `string` | `"eu-west-2"` | no |
| <a name="input_kms_protection_tag_key"></a> [kms\_protection\_tag\_key](#input\_kms\_protection\_tag\_key) | Resource-tag key marking KMS keys protected by the deny-tamper SCP. Keys tagged <key> = "true" cannot be scheduled for deletion, disabled, have rotation disabled or the tag removed except by break-glass; their key policy can only be changed by the pipeline roles or break-glass. Must match the tag the aws/data/kms-key module applies (protection\_tag\_key). | `string` | `"protected"` | no |
| <a name="input_pipeline_role_names"></a> [pipeline\_role\_names](#input\_pipeline\_role\_names) | Names or name patterns (optionally path-prefixed, e.g. "automation/tfc-apply" or "stacksets-exec-*") of the member-account Terraform pipeline roles. Rendered as arn:aws:iam::*:role/<name> and exempted from the deny-tamper reconfiguration statements (Config recorders, GuardDuty/CloudTrail settings, flow logs, protected KMS key policies). These roles are also protected from IAM modification by anyone other than themselves or break-glass. NOT exempt from the destructive statements (break-glass only). | `list(string)` | <pre>[<br/>  "tfc-apply",<br/>  "OrganizationAccountAccessRole",<br/>  "stacksets-exec-*"<br/>]</pre> | no |
| <a name="input_policies"></a> [policies](#input\_policies) | Override map of policies to create, keyed by policy name. When empty (default), the module computes the built-in guardrail set from the templated JSON files. Content is a raw Organizations policy JSON string. | <pre>map(object({<br/>    type    = string<br/>    content = string<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_attachment_ids"></a> [attachment\_ids](#output\_attachment\_ids) | Map of caller attachment key to the attachment resource ID. |
| <a name="output_policy_arns"></a> [policy\_arns](#output\_policy\_arns) | Map of policy name to created Organizations policy ARN. |
| <a name="output_policy_ids"></a> [policy\_ids](#output\_policy\_ids) | Map of policy name to created Organizations policy ID. |
| <a name="output_policy_types"></a> [policy\_types](#output\_policy\_types) | Map of policy name to its Organizations policy type. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "organization_policy" {
  source = "../../modules/aws/organization-policy"

  org_id                  = "o-abc1234567"
  terraform_run_role_arn  = "arn:aws:iam::111111111111:role/tfc-run-role"
  break_glass_role_arn    = "arn:aws:iam::111111111111:role/break-glass"
  log_archive_bucket_name = "sra-log-archive-111111111111"

  pipeline_role_names     = ["tfc-apply", "OrganizationAccountAccessRole"]

  # Attach guardrails to OU/account targets.
  attachments = {
    "baseline@root"        = { policy_key = "scp-baseline", target_id = "r-abcd" }
    "data-perimeter@wklds" = { policy_key = "rcp-data-perimeter", target_id = "ou-abcd-11111111" }
  }
}
```

The built-in guardrail set is computed from the templated JSON in `policies/`.
Override the entire set by passing a non-empty `policies` map.

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
