# backup-vault

KMS-encrypted AWS Backup vault with Compliance-mode Vault Lock (WORM) and AWS
Backup restore testing for the SRA landing zone. Runs in the delegated Backup
account.

Vault Lock is configured in **Compliance mode** (`changeable_for_days` is
non-null): after the cooling-off window elapses the lock cannot be changed or
removed and recovery points cannot be deleted before `min_retention_days` by
anyone, including the root user. This is the control that makes backups
tamper-proof against ransomware and rogue administrators.

`allow_copy_from_organization_id` adds a vault access policy that accepts
`backup:CopyIntoBackupVault` from principals in that organization only, so the
vault can be the destination of the org `BACKUP_POLICY` copy actions. The
`aws-backup` stage uses this for its copy vault (control matrix BCK-01). A vault
without it receives no copies.

Restore testing (`aws_backup_restore_testing_plan` + `_selection`, on unless
`create_restore_testing = false`) periodically restores recovery points from
this vault only. There is one selection per `restore_testing_resource_types`
entry (default `["EBS"]`): EBS selects by a tag condition, every other type
selects all protected resources of that type in the vault. Restore testing
proves recoverability only when the vault receives recovery points (BCK-02).

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
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


- resource.aws_backup_restore_testing_plan.this (modules/aws/backup/backup-vault/main.tf#L104)
- resource.aws_backup_restore_testing_selection.this (modules/aws/backup/backup-vault/main.tf#L121)
- resource.aws_backup_vault.this (modules/aws/backup/backup-vault/main.tf#L58)
- resource.aws_backup_vault_lock_configuration.this (modules/aws/backup/backup-vault/main.tf#L65)
- resource.aws_backup_vault_notifications.this (modules/aws/backup/backup-vault/main.tf#L94)
- resource.aws_backup_vault_policy.copy_in (modules/aws/backup/backup-vault/main.tf#L75)
- resource.aws_iam_role.restore_testing (modules/aws/backup/backup-vault/main.tf#L35)
- resource.aws_iam_role_policy_attachment.restore_testing (modules/aws/backup/backup-vault/main.tf#L52)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_allow_copy_from_organization_id"></a> [allow\_copy\_from\_organization\_id](#input\_allow\_copy\_from\_organization\_id) | AWS Organizations ID (o-...). When set, a vault access policy lets principals in that organization copy recovery points into this vault (backup:CopyIntoBackupVault), so it can be the destination of the org BACKUP\_POLICY copy actions. Null (default) = no vault access policy. | `string` | `null` | no |
| <a name="input_changeable_for_days"></a> [changeable\_for\_days](#input\_changeable\_for\_days) | Cooling-off window (days) during which the Vault Lock can still be changed or deleted. A non-null value enables Compliance mode (WORM); after this window the lock is immutable. Must be at least 3. | `number` | `3` | no |
| <a name="input_create_restore_testing"></a> [create\_restore\_testing](#input\_create\_restore\_testing) | Create the restore testing plan, its selections and (when restore\_testing\_role\_arn is null) the restore-testing role. Set false for a vault that receives no recovery points: testing it proves nothing. | `bool` | `true` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the KMS key used to encrypt recovery points in the vault. Empty string uses the AWS-managed default Backup key. | `string` | `""` | no |
| <a name="input_max_retention_days"></a> [max\_retention\_days](#input\_max\_retention\_days) | Maximum retention (days) allowed for recovery points stored in the vault. | `number` | `3650` | no |
| <a name="input_min_retention_days"></a> [min\_retention\_days](#input\_min\_retention\_days) | Minimum retention (days) enforced on every recovery point stored in the vault. Recovery points cannot be deleted before this age. | `number` | `7` | no |
| <a name="input_notification_topic_arn"></a> [notification\_topic\_arn](#input\_notification\_topic\_arn) | SNS topic that receives this vault's failed backup, copy and restore events (restore-testing restores included) and RECOVERY\_POINT\_MODIFIED. Null (default) = no vault notifications. The topic policy must allow backup.amazonaws.com to publish, and a KMS-encrypted topic's key must allow it too. | `string` | `null` | no |
| <a name="input_partition"></a> [partition](#input\_partition) | AWS partition for the managed-policy ARNs attached to the created restore-testing role (aws, aws-us-gov, aws-cn). | `string` | `"aws"` | no |
| <a name="input_permissions_boundary_arn"></a> [permissions\_boundary\_arn](#input\_permissions\_boundary\_arn) | Permissions-boundary managed policy ARN set on every IAM role this module creates. Required when the roles are created by a member-account tfc-apply role with boundary propagation on (tfc-oidc-baseline enable\_apply\_boundary\_propagation): pass arn:PARTITION:iam::ACCOUNT\_ID:policy/tfc-apply-boundary. Null (default) = no boundary. | `string` | `null` | no |
| <a name="input_restore_testing_plan_name"></a> [restore\_testing\_plan\_name](#input\_restore\_testing\_plan\_name) | Name of the AWS Backup restore testing plan. AWS restricts this to alphanumeric characters and underscores. | `string` | `"org_restore_test"` | no |
| <a name="input_restore_testing_resource_types"></a> [restore\_testing\_resource\_types](#input\_restore\_testing\_resource\_types) | Resource types the restore testing plan restores from this vault, one selection each. EBS selects by the restore\_testing\_tag\_key/value tag; every other type selects all protected resources of that type in the vault. Default ["EBS"]. | `list(string)` | <pre>[<br/>  "EBS"<br/>]</pre> | no |
| <a name="input_restore_testing_role_arn"></a> [restore\_testing\_role\_arn](#input\_restore\_testing\_role\_arn) | ARN of an existing IAM role AWS Backup assumes to perform restore testing jobs. Null (default) creates restore\_testing\_role\_name here (trusting backup.amazonaws.com, with the AWS managed AWSBackupServiceRolePolicyForRestores policy). | `string` | `null` | no |
| <a name="input_restore_testing_role_name"></a> [restore\_testing\_role\_name](#input\_restore\_testing\_role\_name) | Name of the restore-testing IAM role created when restore\_testing\_role\_arn is null. | `string` | `"aws-backup-restore-testing"` | no |
| <a name="input_restore_testing_schedule"></a> [restore\_testing\_schedule](#input\_restore\_testing\_schedule) | Cron schedule expression for the restore testing plan. | `string` | `"cron(0 5 ? * SUN *)"` | no |
| <a name="input_restore_testing_selection_name"></a> [restore\_testing\_selection\_name](#input\_restore\_testing\_selection\_name) | Name of the EBS restore testing selection. Other resource types use <name>\_<type in lower case>. AWS restricts this to alphanumeric characters and underscores. | `string` | `"ebs_restore_test"` | no |
| <a name="input_restore_testing_tag_key"></a> [restore\_testing\_tag\_key](#input\_restore\_testing\_tag\_key) | Resource tag key used to select EBS recovery points for restore testing. Combined with restore\_testing\_tag\_value in a protected\_resource\_conditions string\_equals match. | `string` | `"backup"` | no |
| <a name="input_restore_testing_tag_value"></a> [restore\_testing\_tag\_value](#input\_restore\_testing\_tag\_value) | Resource tag value used to select EBS recovery points for restore testing. | `string` | `"true"` | no |
| <a name="input_selection_window_days"></a> [selection\_window\_days](#input\_selection\_window\_days) | Number of days from which to select recovery points for restore testing (LATEST\_WITHIN\_WINDOW). Must be at least 1. | `number` | `7` | no |
| <a name="input_start_window_hours"></a> [start\_window\_hours](#input\_start\_window\_hours) | Number of hours in which restore testing jobs must start before being cancelled. | `number` | `1` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every taggable resource this module creates (merged after provider default\_tags; resource-specific tags such as Name win). | `map(string)` | `{}` | no |
| <a name="input_vault_name"></a> [vault\_name](#input\_vault\_name) | Name of the AWS Backup vault. | `string` | `"org-backup-vault"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_notification_topic_arn"></a> [notification\_topic\_arn](#output\_notification\_topic\_arn) | SNS topic that receives this vault's failed-job notifications. Null when notification\_topic\_arn was null. |
| <a name="output_restore_testing_plan_arn"></a> [restore\_testing\_plan\_arn](#output\_restore\_testing\_plan\_arn) | The ARN of the restore testing plan, if one was created. |
| <a name="output_restore_testing_role_arn"></a> [restore\_testing\_role\_arn](#output\_restore\_testing\_role\_arn) | ARN of the role restore testing jobs assume (created here when restore\_testing\_role\_arn was null). Null when create\_restore\_testing is false. |
| <a name="output_vault_arn"></a> [vault\_arn](#output\_vault\_arn) | The ARN of the AWS Backup vault. |
| <a name="output_vault_name"></a> [vault\_name](#output\_vault\_name) | The name of the AWS Backup vault. |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "backup_vault" {
  source = "../../modules/aws/backup-vault"

  kms_key_arn              = module.kms_key.key_arn
  restore_testing_role_arn = module.iam_role.restore_testing_role_arn

  # Compliance-mode WORM defaults: 3-day cooling-off, 7-day floor, 10-year ceiling.
}
```

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
