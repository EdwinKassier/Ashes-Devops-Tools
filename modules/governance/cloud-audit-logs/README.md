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
