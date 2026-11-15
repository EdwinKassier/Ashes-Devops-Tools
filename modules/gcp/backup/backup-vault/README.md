# Google Cloud Backup Vault Module

A [Backup and DR Service](https://cloud.google.com/backup-disaster-recovery/docs/concepts/backup-vault)
backup vault with a daily backup plan for Cloud SQL. It is the GCP counterpart
of the AWS locked copy vault (`modules/aws/backup/backup-vault`).

- Every backup in the vault is immutable for `enforced_retention_days`
  (default 35). Nobody can delete it earlier.
- `access_restriction = WITHIN_ORGANIZATION`: backup and restore work only
  inside the organization.
- The vault, the plan and the Cloud SQL instances share one region
  (`location`). Backup and DR needs the plan in the instance region.
- An instance in another project needs `cloud_sql_source_projects`: the module
  grants the vault's service agent `roles/backupdr.cloudSqlOperator` there and
  enables `backupdr.googleapis.com`.

Associating an instance switches it to Cloud SQL enhanced backups: the backup
plan replaces the instance's own backup schedule and retention.

**Irreversible:** `lock_effective_time` locks the minimum enforced retention.
After that time it can only go up. The module sets no lock unless you give a
time.

The caller needs `roles/backupdr.admin` in the vault project and IAM admin in
the source projects. A CMEK-encrypted Cloud SQL instance also needs
`roles/cloudkms.cryptoKeyEncrypterDecrypter` for the `service_account` output
on its key; the module does not grant it.

## Usage

```hcl
module "backup_vault" {
  source = "../../backup/backup-vault"

  project_id              = "my-host-project"
  location                = "europe-west2"
  vault_id                = "prod-vault"
  enforced_retention_days = 35

  cloud_sql_instances       = { orders = "projects/my-service-project/instances/orders-db" }
  cloud_sql_source_projects = { service = "my-service-project" }
}
```

<!-- BEGIN_TF_DOCS -->
Backup Vault Module - Backup and DR Service vault for Cloud SQL

The GCP counterpart of the AWS locked copy vault. A Backup and DR backup
vault keeps every backup immutable for enforced\_retention\_days and, with
access\_restriction WITHIN\_ORGANIZATION, accepts backup and restore only
inside the organization. A daily backup plan protects the listed Cloud SQL
instances (Cloud SQL "enhanced backups").

The vault, its plan and the Cloud SQL instances share one region: Backup and
DR needs the plan in the instance region, and one region keeps the backups
inside gcp.resourceLocations.

Irreversible: lock\_effective\_time locks the minimum enforced retention.
After that time nobody, not even a project owner, can lower it. The module
sets no lock unless lock\_effective\_time is given.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	location =
	project_id =
	vault_id =
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.17, < 2.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 8.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 8.10.0 |



## Resources

The following resources are created:


- resource.google_backup_dr_backup_plan.cloud_sql (modules/gcp/backup/backup-vault/main.tf#L55)
- resource.google_backup_dr_backup_plan_association.cloud_sql (modules/gcp/backup/backup-vault/main.tf#L83)
- resource.google_backup_dr_backup_vault.this (modules/gcp/backup/backup-vault/main.tf#L32)
- resource.google_project_iam_member.cloud_sql_operator (modules/gcp/backup/backup-vault/main.tf#L47)
- resource.google_project_service.backupdr (modules/gcp/backup/backup-vault/main.tf#L24)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_location"></a> [location](#input\_location) | Region of the vault and the backup plan. It must be the region of the Cloud SQL instances: Backup and DR needs the plan in the instance region. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Project that holds the backup vault and its backup plan (the environment host project). | `string` | n/a | yes |
| <a name="input_vault_id"></a> [vault\_id](#input\_vault\_id) | ID of the backup vault. It also prefixes the backup plan and association IDs. | `string` | n/a | yes |
| <a name="input_backup_window_start_hour"></a> [backup\_window\_start\_hour](#input\_backup\_window\_start\_hour) | UTC hour (0-20) at which the daily four-hour backup window opens. | `number` | `2` | no |
| <a name="input_cloud_sql_instances"></a> [cloud\_sql\_instances](#input\_cloud\_sql\_instances) | Cloud SQL instances to protect: key => projects/<project>/instances/<instance>. Every instance must be in location. Empty (default) = a vault with no plan. | `map(string)` | `{}` | no |
| <a name="input_cloud_sql_source_projects"></a> [cloud\_sql\_source\_projects](#input\_cloud\_sql\_source\_projects) | Projects other than project\_id that hold the cloud\_sql\_instances: key => project ID. The vault's service agent gets roles/backupdr.cloudSqlOperator in each, and the Backup and DR API is enabled there. Keys must be known at plan time. | `map(string)` | `{}` | no |
| <a name="input_enforced_retention_days"></a> [enforced\_retention\_days](#input\_enforced\_retention\_days) | Minimum enforced retention of the vault, in days. Every backup in the vault is immutable for this long, and the Cloud SQL plan keeps backups exactly this long. You can raise or lower it until lock\_effective\_time; after that you can only raise it. Cloud SQL accepts at most 3653 days (10 years). | `number` | `35` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels for the vault and the backup plan. | `map(string)` | `{}` | no |
| <a name="input_lock_effective_time"></a> [lock\_effective\_time](#input\_lock\_effective\_time) | IRREVERSIBLE. RFC 3339 UTC time (e.g. 2027-01-01T00:00:00Z) after which the vault's minimum enforced retention is locked: nobody can lower it again. Null (default) = no lock. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_backup_plan_id"></a> [backup\_plan\_id](#output\_backup\_plan\_id) | ID of the daily Cloud SQL backup plan, or null when no instance is listed. |
| <a name="output_enforced_retention_days"></a> [enforced\_retention\_days](#output\_enforced\_retention\_days) | Minimum enforced retention of the vault, in days. |
| <a name="output_protected_instances"></a> [protected\_instances](#output\_protected\_instances) | Cloud SQL instances associated with the plan: key => instance resource name. |
| <a name="output_service_account"></a> [service\_account](#output\_service\_account) | The vault's service agent. The module grants it roles/backupdr.cloudSqlOperator in cloud\_sql\_source\_projects. A CMEK-encrypted Cloud SQL instance also needs roles/cloudkms.cryptoKeyEncrypterDecrypter for this agent on its key. |
| <a name="output_vault_id"></a> [vault\_id](#output\_vault\_id) | Terraform ID of the backup vault (projects/<project>/locations/<location>/backupVaults/<vault\_id>). |
| <a name="output_vault_name"></a> [vault\_name](#output\_vault\_name) | Resource name of the backup vault. |
<!-- END_TF_DOCS -->

## Examples

See [`examples/basic/`](examples/basic/main.tf) for a complete working example.
