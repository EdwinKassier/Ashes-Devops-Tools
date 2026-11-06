# Least-privilege PLAN role (FAST-style "viewer without data access").
#
# roles/viewer is not read-only for data: through the legacy bucket roles it
# reads Cloud Storage objects, and it reads BigQuery table data. A speculative
# plan (any PR, any fork of a workspace's VCS repo) must not be able to read
# workload data, so plan identities get metadata-only predefined viewers plus
# this org custom role, which fills the gaps those viewers leave (bucket and
# Artifact Registry repository metadata, logging configuration, monitoring
# configuration). Every permission is a get / list / getIamPolicy on
# configuration; the var.plan_viewer_permissions validation rejects known
# data-plane permissions (object reads, table data, secret payloads, decrypt,
# log entries, token minting) and anything that is not a get/list.

resource "google_organization_iam_custom_role" "plan_viewer" {
  count = var.enable_plan_viewer_role ? 1 : 0

  org_id      = var.org_id
  role_id     = var.plan_viewer_role_id
  title       = "Landing zone plan viewer"
  description = "Metadata-only read access for Terraform plan identities: get/list/getIamPolicy on configuration, no object, table, secret or log-entry data. Managed by gcp-bootstrap."
  stage       = "GA"
  permissions = sort(distinct(var.plan_viewer_permissions))
}
