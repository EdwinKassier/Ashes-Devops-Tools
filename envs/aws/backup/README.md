# `envs/aws/backup` (workspace `aws-backup`)

Central backup: a KMS-encrypted, Vault-Locked backup vault in the backup account and the organization backup policy attached to the Workloads OU. It reads the `aws-organization` contract. Most inputs default to a key in `config/landing-zone.yaml`; an explicit variable (tfvars or an HCP Terraform workspace variable) wins over the config file. The description of each input names its config key.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.17, < 2.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.46.0, < 7.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.72.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | Home region for both providers, e.g. eu-west-2. Also the region the org backup plan copies recovery points into. Null = org.regions.aws from config/landing-zone.yaml, else eu-west-2. | `string` | `null` | no |
| <a name="input_backup_role_arn"></a> [backup\_role\_arn](#input\_backup\_role\_arn) | ARN of the IAM role AWS Backup assumes in EACH member account under the Workloads OU to run the org backup plan, rendered into the org BACKUP\_POLICY (may use $account). Null (default): the stage deploys backup\_role\_name to every Workloads-OU account via a service-managed StackSet and renders arn:aws:iam::$account:role/<backup\_role\_name>. | `string` | `null` | no |
| <a name="input_backup_role_name"></a> [backup\_role\_name](#input\_backup\_role\_name) | Name of the member-account AWS Backup service role the StackSet deploys when backup\_role\_arn is null. | `string` | `"aws-backup-org-role"` | no |
| <a name="input_changeable_for_days"></a> [changeable\_for\_days](#input\_changeable\_for\_days) | Cooling-off window (days) during which the Compliance-mode Vault Lock can still be changed or deleted. After this window the lock is immutable (WORM). Must be at least 3. | `number` | `3` | no |
| <a name="input_copy_retention_days"></a> [copy\_retention\_days](#input\_copy\_retention\_days) | Days each copy is kept in the central copy vault; must lie between min\_retention\_days and max\_retention\_days. Null = compliance.backup.copy\_retention\_days from config/landing-zone.yaml, else 365. | `number` | `null` | no |
| <a name="input_copy_vault_notification_topic_arn"></a> [copy\_vault\_notification\_topic\_arn](#input\_copy\_vault\_notification\_topic\_arn) | SNS topic in the backup account that receives the central copy vault's failed backup, copy and restore events (restore-testing restores included) and RECOVERY\_POINT\_MODIFIED. Null (default) = no vault notifications. Used only with central copy on. The topic policy (and the key policy of a KMS-encrypted topic) must allow backup.amazonaws.com to publish. | `string` | `null` | no |
| <a name="input_cost_center"></a> [cost\_center](#input\_cost\_center) | Value of the CostCenter cost-allocation tag on every resource in this root. Null = org.cost\_center from config/landing-zone.yaml, else "platform". | `string` | `null` | no |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Extra tags merged into the aws provider default\_tags (after the canonical set, so they may override it). Values must be non-empty. | `map(string)` | `{}` | no |
| <a name="input_dr_region"></a> [dr\_region](#input\_dr\_region) | Second region for a cross-region copy to the member <vault\_name>-cmk vault there (aws-organization creates it from the same compliance.backup.dr\_region). Must differ from aws\_region and be in aws.allowed\_regions (else ["eu-west-2"], the aws-organization default). Null = compliance.backup.dr\_region from config/landing-zone.yaml, else no cross-region copy. | `string` | `null` | no |
| <a name="input_enable_central_copy"></a> [enable\_central\_copy](#input\_enable\_central\_copy) | Copy every member recovery point to a new CMK-encrypted, Compliance-mode Vault-Locked copy vault (org-backup-copy-vault) in the backup account, enable org-wide cross-account backup and point the BACKUP\_POLICY at the <vault\_name>-cmk member vault. IRREVERSIBLE after changeable\_for\_days (UPGRADING.md). Apply aws-organization first with the same compliance.backup settings. Null = compliance.backup.copy\_to\_central\_vault from config/landing-zone.yaml, else false. | `bool` | `null` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of the KMS key used to encrypt recovery points in the vault. Empty string uses the AWS-managed default Backup key. | `string` | `""` | no |
| <a name="input_landing_zone_config_path"></a> [landing\_zone\_config\_path](#input\_landing\_zone\_config\_path) | Path to the single-source landing-zone config (YAML; schema config/landing-zone.example.yaml), absolute or relative to this root. Null = ../../../config/landing-zone.yaml; "" disables the lookup. Read only if the file exists; explicit variables win over its values. | `string` | `null` | no |
| <a name="input_landing_zone_name"></a> [landing\_zone\_name](#input\_landing\_zone\_name) | Landing-zone identifier written to the LandingZone tag on every resource. Null = org.name from config/landing-zone.yaml (the single source shared by every AWS root). The upstream placeholders "ashes" and "my-org" are rejected. | `string` | `null` | no |
| <a name="input_management_account_id"></a> [management\_account\_id](#input\_management\_account\_id) | 12-digit AWS management (payer) account ID. The default provider sets allowed\_account\_ids to this, so Terraform fails fast if the resolved credentials are a different account. Null = aws.management\_account\_id from config/landing-zone.yaml (quote it there); no built-in default. | `string` | `null` | no |
| <a name="input_max_retention_days"></a> [max\_retention\_days](#input\_max\_retention\_days) | Maximum retention (days) allowed for recovery points stored in the vault. | `number` | `3650` | no |
| <a name="input_min_retention_days"></a> [min\_retention\_days](#input\_min\_retention\_days) | Minimum retention (days) enforced on every recovery point stored in the vault. | `number` | `7` | no |
| <a name="input_organization_contract"></a> [organization\_contract](#input\_organization\_contract) | aws-organization stage contract (FAST-style override), the same type in every aws root: organization\_id (o-xxxxxxxxxx), organization\_root\_id (r-xxxx), management\_account\_id, ou\_ids (OU name => OU ID), account\_ids (account key => 12-digit ID), account\_role\_arns (account key => cross-account role ARN). This root needs: account\_ids, account\_role\_arns, ou\_ids. When set, the aws-organization remote state is NOT read. Null = aws.contracts.organization from config/landing-zone.yaml, else the contract output of the organization\_workspace\_name workspace. | <pre>object({<br/>    organization_id       = optional(string)<br/>    organization_root_id  = optional(string)<br/>    management_account_id = optional(string)<br/>    ou_ids                = optional(map(string), {})<br/>    account_ids           = map(string)<br/>    account_role_arns     = optional(map(string), {})<br/>  })</pre> | `null` | no |
| <a name="input_organization_workspace_name"></a> [organization\_workspace\_name](#input\_organization\_workspace\_name) | Name of the Terraform Cloud workspace holding the phase-1 aws-organization root state that this root reads the cross-root contract from. | `string` | `"aws-organization"` | no |
| <a name="input_owner"></a> [owner](#input\_owner) | Value of the Owner cost-allocation tag on every resource in this root (team or distribution list). Null = org.owner from config/landing-zone.yaml, else "platform-team". | `string` | `null` | no |
| <a name="input_restore_testing_role_arn"></a> [restore\_testing\_role\_arn](#input\_restore\_testing\_role\_arn) | ARN of an existing IAM role in the BACKUP account that AWS Backup assumes for restore testing. Null (default) creates aws-backup-restore-testing there (backup.amazonaws.com trust, AWSBackupServiceRolePolicyForRestores). | `string` | `null` | no |
| <a name="input_tfc_aws_dynamic_credentials"></a> [tfc\_aws\_dynamic\_credentials](#input\_tfc\_aws\_dynamic\_credentials) | Injected by Terraform Cloud when the workspace uses AWS dynamic credentials with multiple configurations: default = the management-account role, aliases[backup] = each member account's tfc-plan / tfc-apply role (TFC\_AWS\_PROVIDER\_AUTH\_<alias>, TFC\_AWS\_PLAN\_ROLE\_ARN\_<alias>, TFC\_AWS\_APPLY\_ROLE\_ARN\_<alias>). Leave null for local / legacy runs: the member-account providers then assume account\_role\_arns (OrganizationAccountAccessRole) from management-account credentials. | <pre>object({<br/>    default = object({ shared_config_file = string })<br/>    aliases = map(object({ shared_config_file = string }))<br/>  })</pre> | `null` | no |
| <a name="input_tfc_organization"></a> [tfc\_organization](#input\_tfc\_organization) | Terraform Cloud organization that owns this root's workspace and the aws-organization workspace it reads. Supplied to the backend via the TF\_CLOUD\_ORGANIZATION environment variable (kept out of the code so the same root works across orgs and CI). Null = org.tfc.organization from config/landing-zone.yaml. | `string` | `null` | no |
| <a name="input_vault_name"></a> [vault\_name](#input\_vault\_name) | Name of the AWS Backup vault created in the backup account. Cross-account naming contract: the org BACKUP\_POLICY targets a vault of this name in each member account; aws-organization creates those (its member\_backup\_vault\_name must match). | `string` | `"org-backup-vault"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_backup_policy_id"></a> [backup\_policy\_id](#output\_backup\_policy\_id) | ID of the organization BACKUP\_POLICY attached to the Workloads OU. |
| <a name="output_copy_vault_arn"></a> [copy\_vault\_arn](#output\_copy\_vault\_arn) | ARN of the locked central copy vault in the backup account. Null unless compliance.backup.copy\_to\_central\_vault. |
| <a name="output_vault_arn"></a> [vault\_arn](#output\_vault\_arn) | ARN of the KMS-encrypted, Vault-Locked backup vault in the backup account. |
<!-- END_TF_DOCS -->
