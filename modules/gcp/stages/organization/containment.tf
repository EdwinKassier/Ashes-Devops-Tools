# Bind the containment/protected tag to the audit store so the
# tag-conditioned rule of the containment deny policy (main.tf) applies to the
# audit + access-log buckets and the audit CMEK keyring (and, by tag
# inheritance, its keys and key versions) — and nothing else. Only created when
# enable_admin_containment = true.

locals {
  containment_tag_value = try(module.tags.tag_values["containment-protected"], null)

  # The keyring that holds the audit-logs / audit-analytics keys.
  audit_keyring_id = local.separate_logging_project ? module.audit_cmek[0].keyring_id : module.cmek.keyring_id

  containment_bucket_targets = var.enable_admin_containment ? {
    audit_bucket      = module.audit_logs.storage_bucket_name
    access_log_bucket = module.audit_logs.access_log_bucket_name
  } : {}
}

resource "google_tags_location_tag_binding" "containment_buckets" {
  for_each = local.containment_bucket_targets

  parent    = "//storage.googleapis.com/projects/_/buckets/${each.value}"
  location  = var.default_region
  tag_value = local.containment_tag_value
}

# The audit Log Analytics log bucket (its update/untag is denied by the
# tag-scoped containment rule).
resource "google_tags_location_tag_binding" "containment_log_analytics_bucket" {
  count = var.enable_admin_containment && var.enable_log_analytics ? 1 : 0

  parent    = "//logging.googleapis.com/${module.audit_logs.log_analytics_bucket_id}"
  location  = module.audit_logs.log_analytics_bucket_location
  tag_value = local.containment_tag_value
}

resource "google_tags_location_tag_binding" "containment_audit_keyring" {
  count = var.enable_admin_containment ? 1 : 0

  parent    = "//cloudkms.googleapis.com/${local.audit_keyring_id}"
  location  = var.default_region
  tag_value = local.containment_tag_value
}
