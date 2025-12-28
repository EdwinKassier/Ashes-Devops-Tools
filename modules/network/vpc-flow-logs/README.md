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
