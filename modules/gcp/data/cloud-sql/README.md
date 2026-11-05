# cloud-sql

Creates a managed PostgreSQL Cloud SQL instance that is private by default: no
public IP (peered into a Shared VPC via Private Service Access), TLS-only,
automated backups with point-in-time recovery, IAM database authentication,
optional CMEK, and deletion protection. Optionally creates logical databases and
users.

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

Cloud SQL (PostgreSQL) Module - Main Configuration

Creates a managed PostgreSQL instance that is private by default: no public IP,
peered into a Shared VPC over Private Service Access, TLS-only, with automated
backups + point-in-time recovery, IAM database authentication, optional CMEK,
and deletion protection. Every control is a toggle so admins can compose the
posture they need.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	name = 
	private_network = 
	project_id = 
	region = 
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 7.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.31.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |



## Resources

The following resources are created:


- resource.google_sql_database.this (modules/gcp/data/cloud-sql/main.tf#L89)
- resource.google_sql_database_instance.this (modules/gcp/data/cloud-sql/main.tf#L42)
- resource.google_sql_user.this (modules/gcp/data/cloud-sql/main.tf#L97)
- resource.terraform_data.deletion_protection_guard (modules/gcp/data/cloud-sql/main.tf#L32)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name"></a> [name](#input\_name) | Name of the Cloud SQL instance | `string` | n/a | yes |
| <a name="input_private_network"></a> [private\_network](#input\_private\_network) | The self\_link of the Shared VPC network to peer the instance into via Private Service Access. The instance is reachable on a private IP only. | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The ID of the project where the instance will be created | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | The GCP region to host the instance in (e.g. europe-west1) | `string` | n/a | yes |
| <a name="input_backup_start_time"></a> [backup\_start\_time](#input\_backup\_start\_time) | Daily automated-backup start time in 24h HH:MM UTC | `string` | `"03:00"` | no |
| <a name="input_database_flags"></a> [database\_flags](#input\_database\_flags) | Additional database flags to set on the instance. The cloudsql.iam\_authentication flag is managed by enable\_iam\_authentication and must not be duplicated here. | <pre>list(object({<br/>    name  = string<br/>    value = string<br/>  }))</pre> | `[]` | no |
| <a name="input_database_version"></a> [database\_version](#input\_database\_version) | The PostgreSQL engine version (e.g. POSTGRES\_16) | `string` | `"POSTGRES_16"` | no |
| <a name="input_databases"></a> [databases](#input\_databases) | List of logical database names to create on the instance | `list(string)` | `[]` | no |
| <a name="input_enable_deletion_protection"></a> [enable\_deletion\_protection](#input\_enable\_deletion\_protection) | Prevent accidental destruction of the instance.<br/><br/>When true, the instance's own deletion\_protection API attribute is set and a<br/>terraform\_data guard resource is created with prevent\_destroy = true, so<br/>Terraform refuses to destroy this module. To intentionally remove a protected<br/>instance, set this to false (which also removes the guard) and apply, or run:<br/>  terraform state rm 'module.<name>.terraform\_data.deletion\_protection\_guard' | `bool` | `true` | no |
| <a name="input_enable_high_availability"></a> [enable\_high\_availability](#input\_enable\_high\_availability) | When true the instance runs REGIONAL (synchronous standby, automatic failover); otherwise ZONAL. | `bool` | `false` | no |
| <a name="input_enable_iam_authentication"></a> [enable\_iam\_authentication](#input\_enable\_iam\_authentication) | Enable Cloud SQL IAM database authentication (sets the cloudsql.iam\_authentication flag on). | `bool` | `true` | no |
| <a name="input_enable_point_in_time_recovery"></a> [enable\_point\_in\_time\_recovery](#input\_enable\_point\_in\_time\_recovery) | Enable point-in-time recovery (continuous WAL archiving). Requires backups, which this module always enables. | `bool` | `true` | no |
| <a name="input_encryption_key_name"></a> [encryption\_key\_name](#input\_encryption\_key\_name) | Optional CMEK: the self\_link of a Cloud KMS CryptoKey used to encrypt the instance. Leave null to use Google-managed encryption. | `string` | `null` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | A map of key/value labels to apply to the instance | `map(string)` | `{}` | no |
| <a name="input_maintenance_window_day"></a> [maintenance\_window\_day](#input\_maintenance\_window\_day) | Day of week (1 = Monday … 7 = Sunday) for the maintenance window | `number` | `7` | no |
| <a name="input_maintenance_window_hour"></a> [maintenance\_window\_hour](#input\_maintenance\_window\_hour) | Hour of day (0-23, UTC) for the maintenance window | `number` | `3` | no |
| <a name="input_maintenance_window_update_track"></a> [maintenance\_window\_update\_track](#input\_maintenance\_window\_update\_track) | Maintenance release track: 'canary' (earlier) or 'stable' (later) | `string` | `"stable"` | no |
| <a name="input_tier"></a> [tier](#input\_tier) | The machine type / tier for the instance (e.g. db-custom-1-3840) | `string` | `"db-custom-1-3840"` | no |
| <a name="input_transaction_log_retention_days"></a> [transaction\_log\_retention\_days](#input\_transaction\_log\_retention\_days) | Number of days of transaction (WAL) logs to retain for point-in-time recovery | `number` | `7` | no |
| <a name="input_users"></a> [users](#input\_users) | List of database users to create. For built-in (password) users set `password`<br/>(prefer IAM auth instead). For IAM users set `type = "CLOUD_IAM_USER"` (or<br/>"CLOUD\_IAM\_SERVICE\_ACCOUNT") and omit the password. The whole variable is marked<br/>sensitive because it may carry passwords. | <pre>list(object({<br/>    name     = string<br/>    password = optional(string)<br/>    type     = optional(string, "BUILT_IN")<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_connection_name"></a> [connection\_name](#output\_connection\_name) | The connection name of the instance, used by the Cloud SQL Auth Proxy (<project>:<region>:<name>) |
| <a name="output_name"></a> [name](#output\_name) | The name of the Cloud SQL instance |
| <a name="output_private_ip_address"></a> [private\_ip\_address](#output\_private\_ip\_address) | The private IPv4 address assigned to the instance |
| <a name="output_self_link"></a> [self\_link](#output\_self\_link) | The URI of the Cloud SQL instance |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "postgres" {
  source = "../../modules/gcp/data/cloud-sql"

  project_id      = "my-project-id"
  region          = "europe-west1"
  name            = "app-db"
  private_network = module.vpc.self_link

  enable_high_availability = true

  databases = ["app", "analytics"]

  users = [
    { name = "app-sa@my-project-id.iam", type = "CLOUD_IAM_SERVICE_ACCOUNT" },
  ]
}
```
