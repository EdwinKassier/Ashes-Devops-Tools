# backup-org-policy

Organization `BACKUP_POLICY` for the SRA landing zone, attached to the
**Workloads OU**. The management / backup-admin account owns this policy.

The policy defines an org-wide AWS Backup plan (a daily rule writing to a
central vault with a 365-day lifecycle, selecting resources tagged
`backup = true`) and attaches it to the target OU so every account beneath it
inherits the baseline plan without per-account configuration.

The content uses AWS Organizations `@@assign` syntax and is rendered from a
templated JSON file. Callers can override the entire document by passing a
non-empty `content`.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	backup_role_arn = 
	target_ou_id = 
	
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


- resource.aws_organizations_policy.backup (modules/aws/backup-org-policy/main.tf#L13)
- resource.aws_organizations_policy_attachment.target (modules/aws/backup-org-policy/main.tf#L23)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_backup_role_arn"></a> [backup\_role\_arn](#input\_backup\_role\_arn) | ARN of the IAM role AWS Backup assumes to run backup jobs for the selected resources. | `string` | n/a | yes |
| <a name="input_target_ou_id"></a> [target\_ou\_id](#input\_target\_ou\_id) | ID of the OU the policy is attached to (typically the Workloads OU). | `string` | n/a | yes |
| <a name="input_backup_vault_name"></a> [backup\_vault\_name](#input\_backup\_vault\_name) | Name of the central backup vault the daily rule targets. Rendered into the templated policy. | `string` | `"org-backup-vault"` | no |
| <a name="input_content"></a> [content](#input\_content) | Full JSON policy document. When non-empty this overrides the templated default and is used verbatim (must be valid Organizations backup-policy @@assign JSON). | `string` | `""` | no |
| <a name="input_default_region"></a> [default\_region](#input\_default\_region) | AWS region the org backup plan copies recovery points into. Rendered into the templated policy's regions @@assign. | `string` | `"eu-west-2"` | no |
| <a name="input_policy_name"></a> [policy\_name](#input\_policy\_name) | Name of the AWS Organizations BACKUP\_POLICY. | `string` | `"org-backup-policy"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_policy_arn"></a> [policy\_arn](#output\_policy\_arn) | The ARN of the Organizations backup policy. |
| <a name="output_policy_id"></a> [policy\_id](#output\_policy\_id) | The ID of the Organizations backup policy. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "backup_org_policy" {
  source = "../../modules/aws/backup-org-policy"

  backup_role_arn   = module.iam_role.backup_role_arn
  backup_vault_name = module.backup_vault.vault_name
  target_ou_id      = module.organization.ou_ids["Workloads"]
}
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
