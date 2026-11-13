# Example: configure Cloud Audit Logs export to GCS for an organization.
# Audit logs are stored in a regional, CMEK-encrypted GCS bucket with a 2-year
# retention, as stages/organization configures it.

locals {
  project_id = "my-security-project"
  org_id     = "123456789012"
}

module "audit_logs" {
  source = "../../"

  project_id         = local.project_id
  org_id             = local.org_id
  bucket_location    = "europe-west2"
  log_retention_days = 730 # 2 years

  # Customer-managed key in the bucket's region.
  kms_key_name = "projects/my-security-project/locations/europe-west2/keyRings/audit/cryptoKeys/audit-logs"

  # Set enable_bucket_lock = true only where compliance requires WORM retention:
  # the lock is irreversible.
  enable_bucket_lock = false
}
