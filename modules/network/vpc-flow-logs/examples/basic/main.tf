# Example: export VPC flow logs from a project to a Cloud Storage bucket.
# A log sink captures flow log entries and writes them to the destination bucket
# for long-term retention and analysis.

locals {
  project_id         = "my-workload-project"
  log_archive_bucket = "gs://my-org-flow-logs-archive"
}

module "flow_log_export" {
  source = "../../"

  project_id       = local.project_id
  sink_name        = "vpc-flow-logs-to-gcs"
  destination      = local.log_archive_bucket
  destination_type = "storage"

  description = "Export VPC flow logs to GCS for security audit retention"
}
