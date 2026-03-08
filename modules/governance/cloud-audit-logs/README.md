# Cloud Audit Logs Module

Configures organization-level audit logging with Cloud Storage and optional BigQuery analytics.

## Features

- GCS bucket for long-term log storage
- Optional BigQuery dataset for SQL analytics
- Organization-level audit log sinks
- Configurable retention periods

## Usage

### Basic (GCS Only)
```hcl
module "audit_logs" {
  source = "../../governance/cloud-audit-logs"

  project_id   = "my-admin-project"
  org_id       = "123456789"
  bucket_name  = "org-audit-logs"
  location     = "EU"
}
```

### With BigQuery Analytics
```hcl
module "audit_logs" {
  source = "../../governance/cloud-audit-logs"

  project_id   = "my-admin-project"
  org_id       = "123456789"
  bucket_name  = "org-audit-logs"
  location     = "EU"

  enable_bigquery_analytics = true
  bigquery_location         = "EU"
  bigquery_retention_days   = 365
}
```

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|:--------:|
| project_id | Project ID for resources | string | yes |
| org_id | Organization ID | string | no |
| bucket_name | GCS bucket name | string | yes |
| enable_bigquery_analytics | Enable BigQuery export | bool | no |

## Outputs

| Name | Description |
|------|-------------|
| bucket_name | Audit logs bucket name |
| bigquery_dataset_id | BigQuery dataset ID (if enabled) |
| sink_writer_identity | Sink service account for IAM |

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	project_id = 
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0, < 2.0.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.14.1 |



## Resources

The following resources are created:


- resource.google_bigquery_dataset.audit_logs_analytics (modules/governance/cloud-audit-logs/main.tf#L138)
- resource.google_bigquery_dataset_iam_member.bq_sink_writer (modules/governance/cloud-audit-logs/main.tf#L186)
- resource.google_logging_organization_sink.org_audit_bq_sink (modules/governance/cloud-audit-logs/main.tf#L164)
- resource.google_logging_organization_sink.org_audit_sink (modules/governance/cloud-audit-logs/main.tf#L112)
- resource.google_logging_project_sink.audit_logs_sink (modules/governance/cloud-audit-logs/main.tf#L76)
- resource.google_project_iam_audit_config.project_audit_logs (modules/governance/cloud-audit-logs/main.tf#L93)
- resource.google_storage_bucket.audit_logs (modules/governance/cloud-audit-logs/main.tf#L39)
- resource.google_storage_bucket.audit_logs_access (modules/governance/cloud-audit-logs/main.tf#L2)
- resource.google_storage_bucket_iam_member.audit_logs_access_writer (modules/governance/cloud-audit-logs/main.tf#L32)
- resource.google_storage_bucket_iam_member.log_writer (modules/governance/cloud-audit-logs/main.tf#L86)
- resource.google_storage_bucket_iam_member.org_log_writer (modules/governance/cloud-audit-logs/main.tf#L125)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The ID of the project where the Cloud Audit Logs will be configured | `string` | n/a | yes |
| <a name="input_bigquery_kms_key_name"></a> [bigquery\_kms\_key\_name](#input\_bigquery\_kms\_key\_name) | The KMS key name to encrypt the optional BigQuery audit analytics dataset | `string` | `null` | no |
| <a name="input_bigquery_location"></a> [bigquery\_location](#input\_bigquery\_location) | Location for the BigQuery dataset. Should match or be compatible with bucket\_location. | `string` | `"US"` | no |
| <a name="input_bigquery_retention_days"></a> [bigquery\_retention\_days](#input\_bigquery\_retention\_days) | Number of days to retain audit logs in BigQuery (via partition expiration). | `number` | `365` | no |
| <a name="input_bucket_location"></a> [bucket\_location](#input\_bucket\_location) | The location of the bucket that will store audit logs | `string` | `"US"` | no |
| <a name="input_enable_bigquery_analytics"></a> [enable\_bigquery\_analytics](#input\_enable\_bigquery\_analytics) | Enable BigQuery sink for log analytics. Creates a BigQuery dataset and org-level sink for querying audit logs. | `bool` | `false` | no |
| <a name="input_force_destroy_bucket"></a> [force\_destroy\_bucket](#input\_force\_destroy\_bucket) | When deleting the bucket, automatically delete all objects | `bool` | `false` | no |
| <a name="input_kms_key_name"></a> [kms\_key\_name](#input\_kms\_key\_name) | The KMS key name to encrypt the audit logs bucket (optional) | `string` | `null` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | The number of days to retain audit logs in the storage bucket | `number` | `365` | no |
| <a name="input_org_id"></a> [org\_id](#input\_org\_id) | Organization ID for org-level log sink (optional). When provided, creates an org-level sink that captures audit logs from all projects. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_audit_config_id"></a> [audit\_config\_id](#output\_audit\_config\_id) | The ID of the created audit config |
| <a name="output_bigquery_dataset_id"></a> [bigquery\_dataset\_id](#output\_bigquery\_dataset\_id) | The ID of the BigQuery dataset for audit log analytics (if created) |
| <a name="output_bigquery_dataset_self_link"></a> [bigquery\_dataset\_self\_link](#output\_bigquery\_dataset\_self\_link) | The self link of the BigQuery dataset for audit log analytics (if created) |
| <a name="output_bigquery_sink_name"></a> [bigquery\_sink\_name](#output\_bigquery\_sink\_name) | The name of the BigQuery log sink (if created) |
| <a name="output_bigquery_sink_writer_identity"></a> [bigquery\_sink\_writer\_identity](#output\_bigquery\_sink\_writer\_identity) | The service account that writes audit logs to BigQuery (if created) |
| <a name="output_configured_service"></a> [configured\_service](#output\_configured\_service) | The service for which audit logging is configured |
| <a name="output_log_sink_name"></a> [log\_sink\_name](#output\_log\_sink\_name) | The name of the log sink |
| <a name="output_log_sink_writer_identity"></a> [log\_sink\_writer\_identity](#output\_log\_sink\_writer\_identity) | The service account that writes audit logs to the storage bucket |
| <a name="output_org_log_sink_name"></a> [org\_log\_sink\_name](#output\_org\_log\_sink\_name) | The name of the organization-level log sink (if created) |
| <a name="output_org_log_sink_writer_identity"></a> [org\_log\_sink\_writer\_identity](#output\_org\_log\_sink\_writer\_identity) | The service account that writes org-level audit logs to the storage bucket |
| <a name="output_storage_bucket_name"></a> [storage\_bucket\_name](#output\_storage\_bucket\_name) | The name of the storage bucket where audit logs are exported |
| <a name="output_storage_bucket_url"></a> [storage\_bucket\_url](#output\_storage\_bucket\_url) | The URL of the storage bucket where audit logs are exported |
<!-- END_TF_DOCS -->