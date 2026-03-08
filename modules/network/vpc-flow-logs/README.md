# VPC Flow Logs Export Module

This module creates a log sink for exporting VPC Flow Logs to BigQuery, Cloud Storage, or Pub/Sub. It can optionally create the destination resources and configures the necessary IAM permissions.

## Features

- **Multiple Destinations**: Export to BigQuery, Cloud Storage, or Pub/Sub
- **Auto-create Destinations**: Optionally create BigQuery datasets or Storage buckets
- **Lifecycle Management**: Configure data retention and archival policies
- **IAM Configuration**: Automatically grants sink writer permissions
- **Exclusions**: Filter out unwanted log entries

## Usage

### Export to BigQuery (with dataset creation)

```hcl
module "flow_logs_export" {
  source = "../vpc-flow-logs"

  project_id              = "my-project"
  sink_name               = "vpc-flow-logs-to-bq"
  create_bigquery_dataset = true
  bigquery_dataset_id     = "vpc_flow_logs"
  bigquery_location       = "US"
  
  destination = "bigquery.googleapis.com/projects/my-project/datasets/vpc_flow_logs"

  # Retention
  bigquery_partition_expiration_days = 90
}
```

### Export to Cloud Storage

```hcl
module "flow_logs_export" {
  source = "../vpc-flow-logs"

  project_id            = "my-project"
  sink_name             = "vpc-flow-logs-to-gcs"
  create_storage_bucket = true
  storage_bucket_name   = "my-project-vpc-flow-logs"
  storage_location      = "US"
  
  destination = "storage.googleapis.com/my-project-vpc-flow-logs"

  # Lifecycle
  storage_archive_days   = 90
  storage_retention_days = 365
}
```

### Export to Existing BigQuery Dataset

```hcl
module "flow_logs_export" {
  source = "../vpc-flow-logs"

  project_id          = "my-project"
  sink_name           = "vpc-flow-logs-sink"
  bigquery_dataset_id = "existing_dataset"
  
  destination = "bigquery.googleapis.com/projects/my-project/datasets/existing_dataset"
}
```

### With Custom Filter

```hcl
module "flow_logs_export" {
  source = "../vpc-flow-logs"

  project_id              = "my-project"
  sink_name               = "production-flow-logs"
  create_bigquery_dataset = true
  bigquery_dataset_id     = "prod_flow_logs"
  
  destination = "bigquery.googleapis.com/projects/my-project/datasets/prod_flow_logs"

  # Only capture flow logs from production subnets
  custom_filter = <<-EOT
    resource.type="gce_subnetwork" AND
    log_id("compute.googleapis.com/vpc_flows") AND
    resource.labels.subnetwork_name=~"prod-.*"
  EOT

  # Exclude health check traffic
  exclusions = [
    {
      name        = "exclude-health-checks"
      description = "Exclude health check traffic"
      filter      = "jsonPayload.connection.src_ip=~\"35\\.191\\..*\" OR jsonPayload.connection.src_ip=~\"130\\.211\\..*\""
    }
  ]
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| project_id | The GCP project ID | `string` | n/a | yes |
| sink_name | Name of the log sink | `string` | n/a | yes |
| destination | The destination for the log sink | `string` | `""` | yes |
| create_bigquery_dataset | Whether to create a BigQuery dataset | `bool` | `false` | no |
| bigquery_dataset_id | BigQuery dataset ID | `string` | `"vpc_flow_logs"` | no |
| create_storage_bucket | Whether to create a Storage bucket | `bool` | `false` | no |
| storage_bucket_name | Storage bucket name | `string` | `""` | no |
| custom_filter | Custom filter for the sink | `string` | `""` | no |
| exclusions | Log exclusions | `list(object)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the log sink |
| self_link | The ID of the log sink |
| name | The name of the log sink |
| writer_identity | The service account identity for the sink writer |
| bigquery_dataset_id | The BigQuery dataset ID (if created) |
| storage_bucket_name | The Storage bucket name (if created) |

## Flow Logs Analysis Queries

Once flow logs are exported to BigQuery, you can analyze them with queries like:

### Top Talkers by Bytes
```sql
SELECT
  jsonPayload.connection.src_ip AS source_ip,
  jsonPayload.connection.dest_ip AS dest_ip,
  SUM(CAST(jsonPayload.bytes_sent AS INT64)) AS total_bytes
FROM `project.dataset.compute_googleapis_com_vpc_flows_*`
WHERE _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY))
GROUP BY source_ip, dest_ip
ORDER BY total_bytes DESC
LIMIT 20
```

### Denied Traffic Analysis
```sql
SELECT
  jsonPayload.connection.src_ip,
  jsonPayload.connection.dest_ip,
  jsonPayload.connection.dest_port,
  jsonPayload.disposition
FROM `project.dataset.compute_googleapis_com_vpc_flows_*`
WHERE jsonPayload.disposition = "DENIED"
  AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY))
LIMIT 100
```

<!-- BEGIN_TF_DOCS -->
Copyright 2023 Ashes

VPC Flow Logs Export Module - Main Configuration

Creates a log sink for VPC Flow Logs with destination options
(BigQuery, Cloud Storage, or Pub/Sub) and supporting resources.

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	project_id = 
	sink_name = 
	
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


- resource.google_bigquery_dataset.flow_logs (modules/network/vpc-flow-logs/main.tf#L57)
- resource.google_bigquery_dataset_iam_member.sink_writer (modules/network/vpc-flow-logs/main.tf#L203)
- resource.google_logging_project_sink.flow_logs_sink (modules/network/vpc-flow-logs/main.tf#L26)
- resource.google_pubsub_topic_iam_member.sink_writer (modules/network/vpc-flow-logs/main.tf#L222)
- resource.google_storage_bucket.flow_logs (modules/network/vpc-flow-logs/main.tf#L138)
- resource.google_storage_bucket.flow_logs_access (modules/network/vpc-flow-logs/main.tf#L88)
- resource.google_storage_bucket_iam_member.flow_logs_access_writer (modules/network/vpc-flow-logs/main.tf#L130)
- resource.google_storage_bucket_iam_member.sink_writer (modules/network/vpc-flow-logs/main.tf#L213)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The GCP project ID containing the VPC flow logs | `string` | n/a | yes |
| <a name="input_sink_name"></a> [sink\_name](#input\_sink\_name) | Name of the log sink | `string` | n/a | yes |
| <a name="input_bigquery_dataset_id"></a> [bigquery\_dataset\_id](#input\_bigquery\_dataset\_id) | BigQuery dataset ID for flow logs | `string` | `"vpc_flow_logs"` | no |
| <a name="input_bigquery_delete_contents_on_destroy"></a> [bigquery\_delete\_contents\_on\_destroy](#input\_bigquery\_delete\_contents\_on\_destroy) | Delete dataset contents when destroying | `bool` | `false` | no |
| <a name="input_bigquery_kms_key_name"></a> [bigquery\_kms\_key\_name](#input\_bigquery\_kms\_key\_name) | Customer-managed KMS key used to encrypt the BigQuery dataset when it is created | `string` | `null` | no |
| <a name="input_bigquery_location"></a> [bigquery\_location](#input\_bigquery\_location) | Location for the BigQuery dataset | `string` | `"US"` | no |
| <a name="input_bigquery_partition_expiration_days"></a> [bigquery\_partition\_expiration\_days](#input\_bigquery\_partition\_expiration\_days) | Default partition expiration in days (null for no expiration) | `number` | `90` | no |
| <a name="input_bigquery_table_expiration_days"></a> [bigquery\_table\_expiration\_days](#input\_bigquery\_table\_expiration\_days) | Default table expiration in days (null for no expiration) | `number` | `null` | no |
| <a name="input_bigquery_use_partitioned_tables"></a> [bigquery\_use\_partitioned\_tables](#input\_bigquery\_use\_partitioned\_tables) | Use partitioned tables for better query performance | `bool` | `true` | no |
| <a name="input_create_bigquery_dataset"></a> [create\_bigquery\_dataset](#input\_create\_bigquery\_dataset) | Whether to create a BigQuery dataset for flow logs | `bool` | `false` | no |
| <a name="input_create_storage_bucket"></a> [create\_storage\_bucket](#input\_create\_storage\_bucket) | Whether to create a Cloud Storage bucket for flow logs | `bool` | `false` | no |
| <a name="input_custom_filter"></a> [custom\_filter](#input\_custom\_filter) | Custom filter for the log sink. If empty, defaults to VPC flow logs filter. | `string` | `""` | no |
| <a name="input_description"></a> [description](#input\_description) | Description of the log sink | `string` | `"VPC Flow Logs export sink"` | no |
| <a name="input_destination"></a> [destination](#input\_destination) | The destination for the log sink. Format: bigquery.googleapis.com/projects/[PROJECT]/datasets/[DATASET], storage.googleapis.com/[BUCKET], or pubsub.googleapis.com/projects/[PROJECT]/topics/[TOPIC] | `string` | `""` | no |
| <a name="input_destination_project_id"></a> [destination\_project\_id](#input\_destination\_project\_id) | Project ID where the destination resource exists (defaults to project\_id) | `string` | `""` | no |
| <a name="input_destination_type"></a> [destination\_type](#input\_destination\_type) | Type of destination (bigquery, storage, pubsub). Auto-detected from destination if possible. | `string` | `"bigquery"` | no |
| <a name="input_disabled"></a> [disabled](#input\_disabled) | Whether the sink is disabled | `bool` | `false` | no |
| <a name="input_exclusions"></a> [exclusions](#input\_exclusions) | Log exclusions for the sink | <pre>list(object({<br/>    name        = string<br/>    description = optional(string)<br/>    filter      = string<br/>    disabled    = optional(bool, false)<br/>  }))</pre> | `[]` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels to apply to resources | `map(string)` | `{}` | no |
| <a name="input_pubsub_topic_name"></a> [pubsub\_topic\_name](#input\_pubsub\_topic\_name) | Pub/Sub topic name for flow logs (when using pubsub destination) | `string` | `""` | no |
| <a name="input_storage_archive_days"></a> [storage\_archive\_days](#input\_storage\_archive\_days) | Days before archiving log files (null for no archival) | `number` | `90` | no |
| <a name="input_storage_bucket_name"></a> [storage\_bucket\_name](#input\_storage\_bucket\_name) | Cloud Storage bucket name for flow logs | `string` | `""` | no |
| <a name="input_storage_class"></a> [storage\_class](#input\_storage\_class) | Storage class for the bucket | `string` | `"STANDARD"` | no |
| <a name="input_storage_force_destroy"></a> [storage\_force\_destroy](#input\_storage\_force\_destroy) | Force destroy bucket contents when destroying | `bool` | `false` | no |
| <a name="input_storage_kms_key_name"></a> [storage\_kms\_key\_name](#input\_storage\_kms\_key\_name) | Customer-managed KMS key used to encrypt the Cloud Storage bucket when it is created | `string` | `null` | no |
| <a name="input_storage_location"></a> [storage\_location](#input\_storage\_location) | Location for the Cloud Storage bucket | `string` | `"US"` | no |
| <a name="input_storage_retention_days"></a> [storage\_retention\_days](#input\_storage\_retention\_days) | Days before deleting log files (null for no deletion) | `number` | `365` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_bigquery_dataset"></a> [bigquery\_dataset](#output\_bigquery\_dataset) | The BigQuery dataset resource (if created) |
| <a name="output_bigquery_dataset_id"></a> [bigquery\_dataset\_id](#output\_bigquery\_dataset\_id) | The BigQuery dataset ID (if created) |
| <a name="output_destination"></a> [destination](#output\_destination) | The destination of the log sink |
| <a name="output_id"></a> [id](#output\_id) | The ID of the log sink |
| <a name="output_name"></a> [name](#output\_name) | The name of the log sink |
| <a name="output_self_link"></a> [self\_link](#output\_self\_link) | The ID of the log sink (log sinks use id as identifier) |
| <a name="output_sink"></a> [sink](#output\_sink) | The log sink resource |
| <a name="output_storage_bucket"></a> [storage\_bucket](#output\_storage\_bucket) | The Cloud Storage bucket resource (if created) |
| <a name="output_storage_bucket_name"></a> [storage\_bucket\_name](#output\_storage\_bucket\_name) | The Cloud Storage bucket name (if created) |
| <a name="output_writer_identity"></a> [writer\_identity](#output\_writer\_identity) | The service account identity for the sink writer |
<!-- END_TF_DOCS -->