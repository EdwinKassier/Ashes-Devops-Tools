# Example: export VPC flow logs from a project to a Cloud Storage bucket.
# A log sink captures flow log entries and writes them to the destination bucket
# for long-term retention and analysis.

locals {
  project_id = "my-workload-project"
  # Log sink destination format: storage.googleapis.com/<BUCKET> (not gs://).
  log_archive_bucket = "storage.googleapis.com/my-org-flow-logs-archive"
}

module "flow_log_export" {
  source = "../../"

  # destination_type is derived from the storage.googleapis.com/ prefix.
  project_id  = local.project_id
  sink_name   = "vpc-flow-logs-to-gcs"
  destination = local.log_archive_bucket

  description = "Export VPC flow logs to GCS for security audit retention"
}
