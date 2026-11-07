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
  the delegated backup account. The Vault Lock makes recovery points tamper-proof
  against ransomware / rogue admins; restore testing continuously validates
  recoverability rather than assuming it.
- **backup_org_policy** (`backup-org-policy`, default = management) — an AWS
  Organizations `BACKUP_POLICY` attached to the Workloads OU so every account
  beneath it inherits a baseline daily backup plan without per-account
  configuration.

## Cross-account contract

The two children are joined by **`vault_name`**. The backup account creates the
vault under that name; the management account's org `BACKUP_POLICY` renders the
same name into its daily rule's `target_backup_vault_name`, pointing every
Workloads account at the central Vault-Locked vault.

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
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.72.0 |
| <a name="provider_aws.backup"></a> [aws.backup](#provider\_aws.backup) | 6.72.0 |

## Modules


- backup_org_policy - ../../backup/backup-org-policy
- backup_vault - ../../backup/backup-vault


## Resources

The following resources are created:


- resource.aws_cloudformation_stack_set.backup_role (modules/aws/stages/backup/main.tf#L109)
- resource.aws_cloudformation_stack_set_instance.backup_role (modules/aws/stages/backup/main.tf#L141)
- data source.aws_caller_identity.backup (modules/aws/stages/backup/main.tf#L25)
- data source.aws_partition.backup (modules/aws/stages/backup/main.tf#L30)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_workloads_ou_id"></a> [workloads\_ou\_id](#input\_workloads\_ou\_id) | ID of the OU the org BACKUP\_POLICY is attached to (typically the Workloads OU). Every account beneath it inherits the baseline backup plan. | `string` | n/a | yes |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region the org backup plan copies recovery points into. Rendered into the templated BACKUP\_POLICY's regions @@assign. | `string` | `"eu-west-2"` | no |
| <a name="input_backup_role_arn"></a> [backup\_role\_arn](#input\_backup\_role\_arn) | ARN of the IAM role AWS Backup assumes IN EACH MEMBER ACCOUNT to run the org backup plan's jobs, rendered into the org BACKUP\_POLICY. May use the policy variable $account (arn:aws:iam::$account:role/<name>). Null (default): the stage deploys backup\_role\_name to every account under workloads\_ou\_id via a service-managed CloudFormation StackSet (auto-deploying to new accounts) and renders arn:aws:iam::$account:role/<backup\_role\_name>. | `string` | `null` | no |
| <a name="input_backup_role_name"></a> [backup\_role\_name](#input\_backup\_role\_name) | Name of the member-account AWS Backup service role the StackSet deploys when backup\_role\_arn is null. Trusted by backup.amazonaws.com, with the AWS managed AWSBackupServiceRolePolicyForBackup and AWSBackupServiceRolePolicyForRestores policies. | `string` | `"aws-backup-org-role"` | no |
| <a name="input_backup_role_stack_set_call_as"></a> [backup\_role\_stack\_set\_call\_as](#input\_backup\_role\_stack\_set\_call\_as) | Whether the backup-role StackSet is managed as the management account (SELF) or a CloudFormation delegated administrator (DELEGATED\_ADMIN). This stage's default provider is the management account, so SELF. | `string` | `"SELF"` | no |
| <a name="input_changeable_for_days"></a> [changeable\_for\_days](#input\_changeable\_for\_days) | Cooling-off window (days) during which the Compliance-mode Vault Lock can still be changed or deleted. After this window the lock is immutable (WORM). Must be at least 3. | `number` | `3` | no |
| <a name="input_create_backup_role_stack_set"></a> [create\_backup\_role\_stack\_set](#input\_create\_backup\_role\_stack\_set) | Deploy the member-account Backup service role (backup\_role\_name) from THIS stage through a service-managed StackSet. Default false: aws-organization deploys it (create\_backup\_service\_role there), so the least-privilege aws-backup management role needs no CloudFormation rights. Set true only when aws-backup applies as the phase-0 management role. | `bool` | `false` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the KMS key used to encrypt recovery points in the vault. Empty string uses the AWS-managed default Backup key. | `string` | `""` | no |
| <a name="input_max_retention_days"></a> [max\_retention\_days](#input\_max\_retention\_days) | Maximum retention (days) allowed for recovery points stored in the vault. | `number` | `3650` | no |
| <a name="input_min_retention_days"></a> [min\_retention\_days](#input\_min\_retention\_days) | Minimum retention (days) enforced on every recovery point stored in the vault. Recovery points cannot be deleted before this age. | `number` | `7` | no |
| <a name="input_partition"></a> [partition](#input\_partition) | AWS partition (aws, aws-us-gov, aws-cn) for the member Backup role ARN rendered into the BACKUP\_POLICY. | `string` | `"aws"` | no |
| <a name="input_restore_testing_role_arn"></a> [restore\_testing\_role\_arn](#input\_restore\_testing\_role\_arn) | ARN of an existing IAM role (in the backup account) AWS Backup assumes to perform restore testing jobs. Null (default) creates aws-backup-restore-testing in the backup account. | `string` | `null` | no |
| <a name="input_tfc_apply_boundary_policy_name"></a> [tfc\_apply\_boundary\_policy\_name](#input\_tfc\_apply\_boundary\_policy\_name) | Name of the tfc-apply permissions-boundary managed policy (tfc-oidc-baseline apply\_boundary\_policy\_name). Every IAM role this stage creates in the backup account (the restore-testing role) gets permissions\_boundary = arn:PARTITION:iam::ACCOUNT\_ID:policy/NAME, derived from that account's provider, which the member-account tfc-apply role requires when boundary propagation is on. Null = create roles without a boundary. | `string` | `"tfc-apply-boundary"` | no |
| <a name="input_vault_name"></a> [vault\_name](#input\_vault\_name) | Name of the AWS Backup vault created in the backup account. This is the cross-account naming contract: the management account's org BACKUP\_POLICY targets the vault by this name. | `string` | `"org-backup-vault"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_backup_policy_id"></a> [backup\_policy\_id](#output\_backup\_policy\_id) | ID of the organization BACKUP\_POLICY attached to the Workloads OU. |
| <a name="output_backup_role_arn"></a> [backup\_role\_arn](#output\_backup\_role\_arn) | Member-account backup role ARN rendered into the org BACKUP\_POLICY ($account-templated when the stage's StackSet deploys the role). |
| <a name="output_restore_testing_role_arn"></a> [restore\_testing\_role\_arn](#output\_restore\_testing\_role\_arn) | ARN of the restore-testing role in the backup account (created by the stage unless restore\_testing\_role\_arn was set). |
| <a name="output_vault_arn"></a> [vault\_arn](#output\_vault\_arn) | ARN of the KMS-encrypted, Vault-Locked backup vault in the backup account. |
<!-- END_TF_DOCS -->
