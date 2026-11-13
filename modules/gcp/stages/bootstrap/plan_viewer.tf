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

# Logging configuration reads for organization-plan at the org node (SEC-2).
#
# roles/logging.viewer is not configuration-only: it holds
# logging.logEntries.list, so at the org node it reads the log entries of every
# project (all but Data Access logs). No predefined logging role reads only
# configuration (logging.configWriter also writes). This role holds the reads
# the gcp-organization refresh makes: org sinks (logging.sinks.get) and org
# settings (logging.settings.get) at the org node, and the project sinks, log
# buckets and their tag bindings, links, log-based metrics, views and
# exclusions in the audit project (the admin project or the separate logging
# project). It holds no logging.logEntries.list, logging.privateLogEntries.list,
# logging.views.access or logging.logs.list. Unconditional: organization-plan
# needs it even with enable_plan_viewer_role = false.
locals {
  logging_config_viewer_role = "organizations/${var.org_id}/roles/${var.logging_config_viewer_role_id}"
  logging_config_viewer_permissions = [
    "logging.buckets.get",
    "logging.buckets.list",
    "logging.buckets.listEffectiveTags",
    "logging.buckets.listTagBindings",
    "logging.exclusions.get",
    "logging.exclusions.list",
    "logging.links.get",
    "logging.links.list",
    "logging.logMetrics.get",
    "logging.logMetrics.list",
    "logging.settings.get",
    "logging.sinks.get",
    "logging.sinks.list",
    "logging.views.get",
    "logging.views.list",
  ]
}

resource "google_organization_iam_custom_role" "logging_config_viewer" {
  org_id      = var.org_id
  role_id     = var.logging_config_viewer_role_id
  title       = "Landing zone logging configuration viewer"
  description = "Read-only Cloud Logging configuration (sinks, settings, buckets, links, metrics, views, exclusions) for the organization plan identity. No log entries, private logs or view access. Managed by gcp-bootstrap."
  stage       = "GA"
  permissions = local.logging_config_viewer_permissions
}
