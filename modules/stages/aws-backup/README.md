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
	backup_role_arn = 
	restore_testing_role_arn = 
	workloads_ou_id = 
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |



## Modules


- backup_org_policy - ../../aws/backup-org-policy
- backup_vault - ../../aws/backup-vault




## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_backup_role_arn"></a> [backup\_role\_arn](#input\_backup\_role\_arn) | ARN of the IAM role AWS Backup assumes to run backup jobs for the resources selected by the org backup plan. Rendered into the org BACKUP\_POLICY. | `string` | n/a | yes |
| <a name="input_restore_testing_role_arn"></a> [restore\_testing\_role\_arn](#input\_restore\_testing\_role\_arn) | ARN of the IAM role (in the backup account) AWS Backup assumes to perform restore testing jobs. | `string` | n/a | yes |
| <a name="input_workloads_ou_id"></a> [workloads\_ou\_id](#input\_workloads\_ou\_id) | ID of the OU the org BACKUP\_POLICY is attached to (typically the Workloads OU). Every account beneath it inherits the baseline backup plan. | `string` | n/a | yes |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region the org backup plan copies recovery points into. Rendered into the templated BACKUP\_POLICY's regions @@assign. | `string` | `"eu-west-2"` | no |
| <a name="input_changeable_for_days"></a> [changeable\_for\_days](#input\_changeable\_for\_days) | Cooling-off window (days) during which the Compliance-mode Vault Lock can still be changed or deleted. After this window the lock is immutable (WORM). Must be at least 3. | `number` | `3` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the KMS key used to encrypt recovery points in the vault. Empty string uses the AWS-managed default Backup key. | `string` | `""` | no |
| <a name="input_max_retention_days"></a> [max\_retention\_days](#input\_max\_retention\_days) | Maximum retention (days) allowed for recovery points stored in the vault. | `number` | `3650` | no |
| <a name="input_min_retention_days"></a> [min\_retention\_days](#input\_min\_retention\_days) | Minimum retention (days) enforced on every recovery point stored in the vault. Recovery points cannot be deleted before this age. | `number` | `7` | no |
| <a name="input_vault_name"></a> [vault\_name](#input\_vault\_name) | Name of the AWS Backup vault created in the backup account. This is the cross-account naming contract: the management account's org BACKUP\_POLICY targets the vault by this name. | `string` | `"org-backup-vault"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_backup_policy_id"></a> [backup\_policy\_id](#output\_backup\_policy\_id) | ID of the organization BACKUP\_POLICY attached to the Workloads OU. |
| <a name="output_vault_arn"></a> [vault\_arn](#output\_vault\_arn) | ARN of the KMS-encrypted, Vault-Locked backup vault in the backup account. |
<!-- END_TF_DOCS -->
