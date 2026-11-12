# aws-backup stage

Phase-2 orchestration wrapper that composes the organization backup baseline
across two accounts. Each child module is wired to the correct account through a
provider:

| Provider | Account |
|----------|---------|
| `aws` (default) | organization management account — owns the org `BACKUP_POLICY` |
| `aws.backup` | delegated backup account — owns the Vault-Locked backup vault |

Composed children:

- **backup_vault** (`backup-vault`, `aws.backup`) — a KMS-encrypted AWS Backup
  vault with a Compliance-mode Vault Lock (WORM) and a restore testing plan, in
  the delegated backup account. The Vault Lock makes recovery points in this
  vault tamper-proof against ransomware and rogue admins, but nothing writes to
  this vault: the backup account is not in the Workloads OU. By default its
  restore testing selects only EBS recovery points here, so it does not prove
  recoverability (control matrix BCK-01 and BCK-02; known-gaps A5).
- **copy_vault_key** and **copy_vault** (`kms-key` and `backup-vault`,
  `aws.backup`), only with `enable_central_copy` (default false): a new
  `copy_vault_name` vault, encrypted with a protected customer managed key,
  with a Compliance-mode Vault Lock and a vault policy that accepts copies from
  the organization only. Restore testing moves here (EBS, EC2, RDS, Aurora, S3,
  DynamoDB, EFS). The lock is irreversible after `changeable_for_days`
  (UPGRADING.md).
- **aws_backup_global_settings** (default = management), only with
  `enable_central_copy`: org-wide cross-account backup.
- **backup_org_policy** (`backup-org-policy`, default = management) — an AWS
  Organizations `BACKUP_POLICY` attached to the Workloads OU so every account
  beneath it inherits a baseline daily backup plan without per-account
  configuration.

## Cross-account contract

The policy and the member vaults are joined by **`vault_name`**. The
`BACKUP_POLICY` runs its jobs in each Workloads account and writes to a vault of
that name **in that account** (aws-organization `member_backup_vault_name`
creates it). With `enable_central_copy` or `dr_region` it writes to
`<vault_name>-cmk` instead (aws-organization creates it when the same
`compliance.backup` settings are applied there) and copies each recovery point
to the copy vault (`copy_vault_name`, backup account) and to `<vault_name>-cmk`
in `dr_region`.

The vault is owned by the backup account; the org policy is owned by the
management account (this stage's default provider). Because an Organizations
policy can only be created from the management/delegated-administrator account,
the org policy must run under the default (management) provider, not `aws.backup`.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	workloads_ou_id =
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
| <a name="provider_aws.backup"></a> [aws.backup](#provider\_aws.backup) | 6.72.0 |

## Modules


- backup_org_policy - ../../backup/backup-org-policy
- backup_vault - ../../backup/backup-vault
- copy_vault - ../../backup/backup-vault
- copy_vault_key - ../../data/kms-key


## Resources

The following resources are created:


- resource.aws_backup_global_settings.this (modules/aws/stages/backup/main.tf#L232)
- resource.aws_cloudformation_stack_set.backup_role (modules/aws/stages/backup/main.tf#L157)
- resource.aws_cloudformation_stack_set_instance.backup_role (modules/aws/stages/backup/main.tf#L189)
- data source.aws_caller_identity.backup (modules/aws/stages/backup/main.tf#L37)
- data source.aws_partition.backup (modules/aws/stages/backup/main.tf#L42)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_workloads_ou_id"></a> [workloads\_ou\_id](#input\_workloads\_ou\_id) | ID of the OU the org BACKUP\_POLICY is attached to (typically the Workloads OU). Every account beneath it inherits the baseline backup plan. | `string` | n/a | yes |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region the org backup plan copies recovery points into. Rendered into the templated BACKUP\_POLICY's regions @@assign. | `string` | `"eu-west-2"` | no |
| <a name="input_backup_account_id"></a> [backup\_account\_id](#input\_backup\_account\_id) | 12-digit ID of the backup account (the aws.backup provider's account). The copy destination ARN and the copy vault key policy use it. Needed when enable\_central\_copy is true. | `string` | `null` | no |
| <a name="input_backup_role_arn"></a> [backup\_role\_arn](#input\_backup\_role\_arn) | ARN of the IAM role AWS Backup assumes IN EACH MEMBER ACCOUNT to run the org backup plan's jobs, rendered into the org BACKUP\_POLICY. May use the policy variable $account (arn:aws:iam::$account:role/<name>). Null (default): the stage deploys backup\_role\_name to every account under workloads\_ou\_id via a service-managed CloudFormation StackSet (auto-deploying to new accounts) and renders arn:aws:iam::$account:role/<backup\_role\_name>. | `string` | `null` | no |
| <a name="input_backup_role_name"></a> [backup\_role\_name](#input\_backup\_role\_name) | Name of the member-account AWS Backup service role the StackSet deploys when backup\_role\_arn is null. Trusted by backup.amazonaws.com, with the AWS managed AWSBackupServiceRolePolicyForBackup and AWSBackupServiceRolePolicyForRestores policies. | `string` | `"aws-backup-org-role"` | no |
| <a name="input_backup_role_stack_set_call_as"></a> [backup\_role\_stack\_set\_call\_as](#input\_backup\_role\_stack\_set\_call\_as) | Whether the backup-role StackSet is managed as the management account (SELF) or a CloudFormation delegated administrator (DELEGATED\_ADMIN). This stage's default provider is the management account, so SELF. | `string` | `"SELF"` | no |
| <a name="input_changeable_for_days"></a> [changeable\_for\_days](#input\_changeable\_for\_days) | Cooling-off window (days) during which the Compliance-mode Vault Lock can still be changed or deleted. After this window the lock is immutable (WORM). Must be at least 3. | `number` | `3` | no |
| <a name="input_copy_retention_days"></a> [copy\_retention\_days](#input\_copy\_retention\_days) | Days each copy is kept in the central copy vault. Must lie between min\_retention\_days and max\_retention\_days (the copy vault's Vault Lock), or every copy job fails. | `number` | `365` | no |
| <a name="input_copy_vault_key_admin_arn"></a> [copy\_vault\_key\_admin\_arn](#input\_copy\_vault\_key\_admin\_arn) | Principal granted key administration (no usage, no kms:PutKeyPolicy) on the created copy vault key. Null = the backup account's tfc-apply role, the role that applies this stage there. | `string` | `null` | no |
| <a name="input_copy_vault_key_policy_admin_role_name"></a> [copy\_vault\_key\_policy\_admin\_role\_name](#input\_copy\_vault\_key\_policy\_admin\_role\_name) | Role name in the backup account granted kms:PutKeyPolicy, and nothing else, on the created copy vault key. Default break-glass: the member break-glass role aws-organization deploys (enable\_member\_break\_glass\_role); it must exist before the key is created. Null = the key admin also holds kms:PutKeyPolicy. | `string` | `"break-glass"` | no |
| <a name="input_copy_vault_kms_key_arn"></a> [copy\_vault\_kms\_key\_arn](#input\_copy\_vault\_kms\_key\_arn) | ARN of an existing customer managed key in the backup account for the copy vault. Null (default) creates one (alias backup-copy-vault): rotating, tagged protected = true, usable by backup-account principals only through AWS Backup and the restore services. | `string` | `null` | no |
| <a name="input_copy_vault_name"></a> [copy\_vault\_name](#input\_copy\_vault\_name) | Name of the locked central copy vault in the backup account. | `string` | `"org-backup-copy-vault"` | no |
| <a name="input_copy_vault_notification_topic_arn"></a> [copy\_vault\_notification\_topic\_arn](#input\_copy\_vault\_notification\_topic\_arn) | SNS topic in the backup account that receives the copy vault's failed backup, copy and restore events (restore-testing restores included) and RECOVERY\_POINT\_MODIFIED. Null (default) = no vault notifications. Used only with enable\_central\_copy. The topic policy (and the key policy of a KMS-encrypted topic) must allow backup.amazonaws.com to publish. | `string` | `null` | no |
| <a name="input_create_backup_role_stack_set"></a> [create\_backup\_role\_stack\_set](#input\_create\_backup\_role\_stack\_set) | Deploy the member-account Backup service role (backup\_role\_name) from THIS stage through a service-managed StackSet. Default false: aws-organization deploys it (create\_backup\_service\_role there), so the least-privilege aws-backup management role needs no CloudFormation rights. Set true only when aws-backup applies as the phase-0 management role. | `bool` | `false` | no |
| <a name="input_dr_copy_retention_days"></a> [dr\_copy\_retention\_days](#input\_dr\_copy\_retention\_days) | Days each cross-region copy is kept in the member DR vault. | `number` | `35` | no |
| <a name="input_dr_region"></a> [dr\_region](#input\_dr\_region) | Second region for a cross-region copy: the BACKUP\_POLICY copies each recovery point to the <vault\_name>-cmk vault in this region of the same member account (aws-organization member\_backup\_dr\_region creates it). Also points the policy at the <vault\_name>-cmk member vault. Must differ from aws\_region and be an allowed region. Null (default) = no cross-region copy. | `string` | `null` | no |
| <a name="input_enable_central_copy"></a> [enable\_central\_copy](#input\_enable\_central\_copy) | Copy every member recovery point to a new CMK-encrypted, Compliance-mode Vault-Locked copy vault (copy\_vault\_name) in the backup account. Also enables org-wide cross-account backup in the management account, points the BACKUP\_POLICY at the <vault\_name>-cmk member vault (aws-organization member\_backup\_vault\_encryption = cmk must have created it) and moves restore testing to the copy vault. IRREVERSIBLE after changeable\_for\_days: the lock cannot be removed and copies cannot be deleted before min\_retention\_days. Default false. | `bool` | `false` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the KMS key used to encrypt recovery points in the vault. Empty string uses the AWS-managed default Backup key. | `string` | `""` | no |
| <a name="input_management_account_id"></a> [management\_account\_id](#input\_management\_account\_id) | 12-digit management account ID, used by the copy vault key module. Needed when enable\_central\_copy is true and copy\_vault\_kms\_key\_arn is null. | `string` | `null` | no |
| <a name="input_max_retention_days"></a> [max\_retention\_days](#input\_max\_retention\_days) | Maximum retention (days) allowed for recovery points stored in the vault. | `number` | `3650` | no |
| <a name="input_member_vault_name"></a> [member\_vault\_name](#input\_member\_vault\_name) | Name of the member-account vault the BACKUP\_POLICY writes to. Null derives it: <vault\_name>-cmk with enable\_central\_copy or dr\_region, else vault\_name. | `string` | `null` | no |
| <a name="input_min_retention_days"></a> [min\_retention\_days](#input\_min\_retention\_days) | Minimum retention (days) enforced on every recovery point stored in the vault. Recovery points cannot be deleted before this age. | `number` | `7` | no |
| <a name="input_organization_id"></a> [organization\_id](#input\_organization\_id) | AWS Organizations ID (o-...). The copy vault's access policy admits copies from principals in this organization only. Needed when enable\_central\_copy is true. | `string` | `null` | no |
| <a name="input_partition"></a> [partition](#input\_partition) | AWS partition (aws, aws-us-gov, aws-cn) for the member Backup role ARN rendered into the BACKUP\_POLICY. | `string` | `"aws"` | no |
| <a name="input_restore_testing_role_arn"></a> [restore\_testing\_role\_arn](#input\_restore\_testing\_role\_arn) | ARN of an existing IAM role (in the backup account) AWS Backup assumes to perform restore testing jobs. Null (default) creates aws-backup-restore-testing in the backup account. | `string` | `null` | no |
| <a name="input_retention_days"></a> [retention\_days](#input\_retention\_days) | Days the org BACKUP\_POLICY daily rule keeps each recovery point in the member vault. | `number` | `365` | no |
| <a name="input_tfc_apply_boundary_policy_name"></a> [tfc\_apply\_boundary\_policy\_name](#input\_tfc\_apply\_boundary\_policy\_name) | Name of the tfc-apply permissions-boundary managed policy (tfc-oidc-baseline apply\_boundary\_policy\_name). Every IAM role this stage creates in the backup account (the restore-testing role) gets permissions\_boundary = arn:PARTITION:iam::ACCOUNT\_ID:policy/NAME, derived from that account's provider, which the member-account tfc-apply role requires when boundary propagation is on. Null = create roles without a boundary. | `string` | `"tfc-apply-boundary"` | no |
| <a name="input_vault_name"></a> [vault\_name](#input\_vault\_name) | Name of the AWS Backup vault created in the backup account. This is the cross-account naming contract: the org BACKUP\_POLICY targets a vault of this name in each member account, which the member-account StackSet creates (aws-organization member\_backup\_vault\_name must match). | `string` | `"org-backup-vault"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_backup_policy_id"></a> [backup\_policy\_id](#output\_backup\_policy\_id) | ID of the organization BACKUP\_POLICY attached to the Workloads OU. |
| <a name="output_backup_role_arn"></a> [backup\_role\_arn](#output\_backup\_role\_arn) | Member-account backup role ARN rendered into the org BACKUP\_POLICY ($account-templated when the stage's StackSet deploys the role). |
| <a name="output_copy_destination_vault_arns"></a> [copy\_destination\_vault\_arns](#output\_copy\_destination\_vault\_arns) | Vault ARNs the BACKUP\_POLICY copies each recovery point to: the central copy vault (enable\_central\_copy) and the member DR vault ($account, dr\_region). Empty by default. |
| <a name="output_copy_vault_arn"></a> [copy\_vault\_arn](#output\_copy\_vault\_arn) | ARN of the locked central copy vault in the backup account. Null unless enable\_central\_copy. |
| <a name="output_policy_target_vault_name"></a> [policy\_target\_vault\_name](#output\_policy\_target\_vault\_name) | Member-account vault the BACKUP\_POLICY daily rule writes to. |
| <a name="output_restore_testing_role_arn"></a> [restore\_testing\_role\_arn](#output\_restore\_testing\_role\_arn) | ARN of the restore-testing role in the backup account (created by the stage unless restore\_testing\_role\_arn was set). With enable\_central\_copy it is the copy vault's role. |
| <a name="output_vault_arn"></a> [vault\_arn](#output\_vault\_arn) | ARN of the KMS-encrypted, Vault-Locked backup vault in the backup account. |
<!-- END_TF_DOCS -->
