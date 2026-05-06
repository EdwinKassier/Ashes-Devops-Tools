# Example: configure Cloud Audit Logs export to GCS for an organization.
# Audit logs are stored in an encrypted GCS bucket with a 2-year retention.

locals {
  project_id = "my-security-project"
  org_id     = "123456789012"
}

module "audit_logs" {
  source = "../../"

  project_id         = local.project_id
  org_id             = local.org_id
  bucket_location    = "US"
  log_retention_days = 730  # 2 years
}

output "audit_log_bucket" {
  description = "GCS bucket name where audit logs are stored"
  value       = module.audit_logs.storage_bucket_name
}

output "log_sink_writer_identity" {
  description = "Service account identity of the log sink — grant it Storage Object Creator on the bucket"
  value       = module.audit_logs.log_sink_writer_identity
}
