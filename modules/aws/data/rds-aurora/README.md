# rds-aurora

Managed PostgreSQL on Amazon Aurora for the landing zone. Composes an
`aws_rds_cluster` (engine `aurora-postgresql`) with one or more
`aws_rds_cluster_instance`s (default 2, for writer + reader HA), a private
`aws_db_subnet_group`, and a Terraform-side deletion guard.

Secure-by-default:

- **Encryption at rest** is always on with a **required customer-managed KMS
  key** (`kms_key_id`) — the default AWS-managed key is deliberately not allowed.
- The cluster lives in **private** subnets and instances are never
  `publicly_accessible`.
- `deletion_protection` defaults **true**, and a `terraform_data` guard with
  `prevent_destroy` additionally aborts an accidental `terraform destroy` at
  plan time (remove the guard from configuration to intentionally tear the
  cluster down).
- Automated backups are retained (default 7 days) and a final snapshot is taken
  on deletion.
- **IAM database authentication** is on by default.
- **Performance Insights** is on, encrypted with the CMEK.
- The **master password is managed by RDS in Secrets Manager** by default
  (`manage_master_user_password = true`) so it never lands in Terraform state.

Aurora Serverless v2 is opt-in (`enable_serverless_v2`): the cluster keeps
`engine_mode = "provisioned"` and gains a `serverlessv2_scaling_configuration`,
while instances switch to the `db.serverless` class.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	kms_key_id =
	name =
	security_group_ids =
	subnet_ids =
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
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |



## Resources

The following resources are created:


- resource.aws_db_subnet_group.this (modules/aws/data/rds-aurora/main.tf#L35)
- resource.aws_rds_cluster.this (modules/aws/data/rds-aurora/main.tf#L44)
- resource.aws_rds_cluster_instance.this (modules/aws/data/rds-aurora/main.tf#L97)
- resource.terraform_data.deletion_guard (modules/aws/data/rds-aurora/main.tf#L133)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_kms_key_id"></a> [kms\_key\_id](#input\_kms\_key\_id) | Customer-managed KMS key ARN used to encrypt cluster storage (required — the default AWS-managed key is deliberately not allowed). | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Cluster identifier. Also used to derive the DB subnet group name and the default final snapshot identifier. | `string` | n/a | yes |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | VPC security group IDs controlling network access to the cluster. | `list(string)` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | Subnet IDs for the DB subnet group. These MUST be PRIVATE subnets — the cluster is never publicly accessible. | `list(string)` | n/a | yes |
| <a name="input_apply_immediately"></a> [apply\_immediately](#input\_apply\_immediately) | Whether modifications are applied immediately rather than during the next maintenance window. | `bool` | `false` | no |
| <a name="input_backup_retention_period"></a> [backup\_retention\_period](#input\_backup\_retention\_period) | Number of days automated backups are retained. | `number` | `7` | no |
| <a name="input_database_name"></a> [database\_name](#input\_database\_name) | Name of the initial database created in the cluster. | `string` | `"app"` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Whether the cluster has AWS-side deletion protection. Secure default is true; a terraform\_data guard additionally blocks accidental `terraform destroy`. | `bool` | `true` | no |
| <a name="input_enable_serverless_v2"></a> [enable\_serverless\_v2](#input\_enable\_serverless\_v2) | Whether to run the cluster as Aurora Serverless v2 (engine\_mode provisioned + serverlessv2\_scaling\_configuration, instances use db.serverless). | `bool` | `false` | no |
| <a name="input_enabled_cloudwatch_logs_exports"></a> [enabled\_cloudwatch\_logs\_exports](#input\_enabled\_cloudwatch\_logs\_exports) | Log types to export to CloudWatch Logs (e.g. postgresql). | `list(string)` | <pre>[<br/>  "postgresql"<br/>]</pre> | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | aurora-postgresql engine version (e.g. 16.6). | `string` | `"16.6"` | no |
| <a name="input_final_snapshot_identifier"></a> [final\_snapshot\_identifier](#input\_final\_snapshot\_identifier) | Identifier for the final snapshot taken on deletion. Defaults to <name>-final when empty. Ignored when skip\_final\_snapshot is true. | `string` | `""` | no |
| <a name="input_iam_database_authentication_enabled"></a> [iam\_database\_authentication\_enabled](#input\_iam\_database\_authentication\_enabled) | Whether to enable IAM database authentication. | `bool` | `true` | no |
| <a name="input_instance_class"></a> [instance\_class](#input\_instance\_class) | Instance class for the cluster instances. Ignored when enable\_serverless\_v2 is true (db.serverless is used instead). | `string` | `"db.r6g.large"` | no |
| <a name="input_instance_count"></a> [instance\_count](#input\_instance\_count) | Number of cluster instances (writer + readers). Defaults to 2 for HA (one writer, one reader). | `number` | `2` | no |
| <a name="input_manage_master_user_password"></a> [manage\_master\_user\_password](#input\_manage\_master\_user\_password) | When true (default), RDS generates and manages the master password in Secrets Manager so it is never written to Terraform state. When false, master\_password must be supplied. | `bool` | `true` | no |
| <a name="input_master_password"></a> [master\_password](#input\_master\_password) | Master password. Only used when manage\_master\_user\_password is false. Ephemeral and written with the write-only master\_password\_wo argument, so it never enters plan or state; it may be fed from an ephemeral resource (e.g. aws\_secretsmanager\_secret\_version). Prefer manage\_master\_user\_password = true (RDS-managed secret). | `string` | `null` | no |
| <a name="input_master_password_version"></a> [master\_password\_version](#input\_master\_password\_version) | Write-only version counter for master\_password (only used when manage\_master\_user\_password is false). Increment to rotate the password. | `number` | `1` | no |
| <a name="input_master_user_secret_kms_key_id"></a> [master\_user\_secret\_kms\_key\_id](#input\_master\_user\_secret\_kms\_key\_id) | KMS key ARN that encrypts the RDS-managed master user secret. Empty uses the default aws/secretsmanager key. Only used when manage\_master\_user\_password is true. | `string` | `""` | no |
| <a name="input_master_username"></a> [master\_username](#input\_master\_username) | Master (admin) username for the cluster. | `string` | `"dbadmin"` | no |
| <a name="input_monitoring_interval"></a> [monitoring\_interval](#input\_monitoring\_interval) | Enhanced monitoring interval in seconds (0 = disabled, the default). Set to 1/5/10/15/30/60 to enable; requires monitoring\_role\_arn. | `number` | `0` | no |
| <a name="input_monitoring_role_arn"></a> [monitoring\_role\_arn](#input\_monitoring\_role\_arn) | IAM role ARN RDS uses for enhanced monitoring. Required when monitoring\_interval > 0. | `string` | `""` | no |
| <a name="input_performance_insights_kms_key_arn"></a> [performance\_insights\_kms\_key\_arn](#input\_performance\_insights\_kms\_key\_arn) | KMS key ARN encrypting Performance Insights data. Defaults to kms\_key\_id when empty. | `string` | `""` | no |
| <a name="input_port"></a> [port](#input\_port) | TCP port the database listens on. | `number` | `5432` | no |
| <a name="input_preferred_backup_window"></a> [preferred\_backup\_window](#input\_preferred\_backup\_window) | Daily time range (UTC) during which automated backups are taken (hh24:mi-hh24:mi). | `string` | `"02:00-03:00"` | no |
| <a name="input_preferred_maintenance_window"></a> [preferred\_maintenance\_window](#input\_preferred\_maintenance\_window) | Weekly time range (UTC) for system maintenance (ddd:hh24:mi-ddd:hh24:mi). | `string` | `"sun:04:00-sun:05:00"` | no |
| <a name="input_serverless_v2_max_capacity"></a> [serverless\_v2\_max\_capacity](#input\_serverless\_v2\_max\_capacity) | Maximum Aurora Capacity Units (ACU) for Serverless v2. Only used when enable\_serverless\_v2 is true. | `number` | `4` | no |
| <a name="input_serverless_v2_min_capacity"></a> [serverless\_v2\_min\_capacity](#input\_serverless\_v2\_min\_capacity) | Minimum Aurora Capacity Units (ACU) for Serverless v2. Only used when enable\_serverless\_v2 is true. | `number` | `0.5` | no |
| <a name="input_skip_final_snapshot"></a> [skip\_final\_snapshot](#input\_skip\_final\_snapshot) | Whether to skip the final snapshot on cluster deletion. Secure default is false so a snapshot is always taken. | `bool` | `false` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to every resource created by this module. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cluster_arn"></a> [cluster\_arn](#output\_cluster\_arn) | ARN of the Aurora cluster. |
| <a name="output_cluster_identifier"></a> [cluster\_identifier](#output\_cluster\_identifier) | Identifier of the Aurora cluster. |
| <a name="output_database_name"></a> [database\_name](#output\_database\_name) | Name of the initial database. |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | Writer (primary) endpoint of the cluster. |
| <a name="output_instance_identifiers"></a> [instance\_identifiers](#output\_instance\_identifiers) | Identifiers of the cluster instances (writer + readers). |
| <a name="output_master_user_secret_arn"></a> [master\_user\_secret\_arn](#output\_master\_user\_secret\_arn) | ARN of the RDS-managed master user secret in Secrets Manager. Null when manage\_master\_user\_password is false. |
| <a name="output_port"></a> [port](#output\_port) | Port the database listens on. |
| <a name="output_publicly_accessible"></a> [publicly\_accessible](#output\_publicly\_accessible) | Whether ANY cluster instance is publicly accessible. Always false — instances are hard-wired to publicly\_accessible = false; exported so composing stages can assert it. |
| <a name="output_reader_endpoint"></a> [reader\_endpoint](#output\_reader\_endpoint) | Reader endpoint of the cluster (load-balances across replicas). |
<!-- END_TF_DOCS -->

## Usage

```hcl
module "orders_db" {
  source = "../../modules/aws/data/rds-aurora"

  name               = "orders-db"
  engine_version     = "16.6"
  kms_key_id         = aws_kms_key.rds.arn
  subnet_ids         = module.vpc.subnet_ids_by_tier["isolated"]
  security_group_ids = [aws_security_group.db.id]
  database_name      = "orders"
  instance_count     = 2

  # Password is generated and stored in Secrets Manager (never in state).
  manage_master_user_password = true
}
```

The generated master-user secret ARN is exposed as the
`master_user_secret_arn` output for wiring into application configuration.
