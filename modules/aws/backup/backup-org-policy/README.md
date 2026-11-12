# backup-org-policy

Organization `BACKUP_POLICY` for the SRA landing zone, attached to the
**Workloads OU**. The management / backup-admin account owns this policy.

The policy defines an org-wide AWS Backup plan (a daily rule writing to a vault
named `backup_vault_name` in each member account, with a `retention_days`
lifecycle (default 365), selecting resources tagged `backup = true`) and
attaches it to the target OU so every account beneath it inherits the baseline
plan without per-account configuration.

`copy_actions` (empty by default) copies each daily recovery point to other
vaults, for example a locked vault in the backup account or a vault in a DR
region. A destination ARN may use the policy variable `$account`.

The content uses AWS Organizations `@@assign` syntax and is built with
`jsonencode()`. Callers can override the entire document by passing a
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
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.17, < 2.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.72.0 |



## Resources

The following resources are created:


- resource.aws_organizations_policy.backup (modules/aws/backup/backup-org-policy/main.tf#L51)
- resource.aws_organizations_policy_attachment.target (modules/aws/backup/backup-org-policy/main.tf#L59)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_backup_role_arn"></a> [backup\_role\_arn](#input\_backup\_role\_arn) | ARN of the IAM role AWS Backup assumes to run backup jobs for the selected resources. | `string` | n/a | yes |
| <a name="input_target_ou_id"></a> [target\_ou\_id](#input\_target\_ou\_id) | ID of the OU the policy is attached to (typically the Workloads OU). | `string` | n/a | yes |
| <a name="input_backup_vault_name"></a> [backup\_vault\_name](#input\_backup\_vault\_name) | Name of the vault the daily rule writes to in each member account (the policy runs its jobs in the member account). | `string` | `"org-backup-vault"` | no |
| <a name="input_content"></a> [content](#input\_content) | Full JSON policy document. When non-empty this overrides the generated default and is used verbatim (must be valid Organizations backup-policy @@assign JSON). | `string` | `""` | no |
| <a name="input_copy_actions"></a> [copy\_actions](#input\_copy\_actions) | Copy each daily recovery point to these vaults (rules.daily.copy\_actions). destination\_vault\_arn may use the Organizations backup policy variable $account for the member account. Cross-account copy needs org-wide cross-account backup and a customer managed key on the source vault. delete\_after\_days must fit the destination vault's Vault Lock min/max retention, or the copy job fails. Empty (default) = no copy. | <pre>list(object({<br/>    destination_vault_arn = string<br/>    delete_after_days     = number<br/>  }))</pre> | `[]` | no |
| <a name="input_default_region"></a> [default\_region](#input\_default\_region) | AWS region the org backup plan writes recovery points to (single region). Rendered into the policy's regions @@assign. Copies to other regions or accounts come from copy\_actions. | `string` | `"eu-west-2"` | no |
| <a name="input_policy_name"></a> [policy\_name](#input\_policy\_name) | Name of the AWS Organizations BACKUP\_POLICY. | `string` | `"org-backup-policy"` | no |
| <a name="input_retention_days"></a> [retention\_days](#input\_retention\_days) | Days the daily rule keeps each recovery point in the member vault (lifecycle delete\_after\_days). | `number` | `365` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every taggable resource this module creates (merged after provider default\_tags; resource-specific tags such as Name win). | `map(string)` | `{}` | no |

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
