# Impersonation is OPTIONAL: leave terraform_admin_email null in TFC —
# dynamic credentials already run plan as <prefix>-projects-plan and apply as
# <prefix>-projects-apply. Set it only for a deliberate local human run.
#
# IAM batching is off. projects-apply grants folder roles through a delegated
# folderIamAdmin whose IAM conditions each allow at most 10 roles (one
# modifiedGrantsByRole hasOnly() list per condition, set by gcp-organization).
# With batching on, the provider merges the google_folder_iam_member changes on
# one folder into a single setIamPolicy call. That call can change roles from
# two conditions at once, and IAM then denies it. Without batching, each
# binding is its own read-modify-write (serialized per folder by the provider).
provider "google" {
  region                      = local.default_region
  impersonate_service_account = var.terraform_admin_email
  default_labels              = local.gcp_default_labels

  batching {
    enable_batching = false
  }
}

provider "google-beta" {
  region                      = local.default_region
  impersonate_service_account = var.terraform_admin_email
  default_labels              = local.gcp_default_labels

  batching {
    enable_batching = false
  }
}

provider "random" {}

# Canonical label set written by EVERY google / google-beta provider in this root
# (default_labels) — the GCP twin of the AWS roots' default_tags (ManagedBy,
# LandingZone, Workspace, Environment, CostCenter, Owner), in GCP label form
# (lowercase keys and values, hyphens). Values are plan-known and label-valid
# (project_prefix and environment are validated lowercase; cost-center and
# owner are made label-safe below), so there is no perpetual diff. The
# provider MERGES these into each resource's effective labels: a module-level
# `labels` entry with the same key wins, so modules never fight the provider.
locals {
  gcp_default_labels = {
    managed-by   = "terraform"
    landing-zone = local.project_prefix
    workspace    = "gcp-projects"
    environment  = "shared"
    cost-center  = local.gcp_label_cost_center
    owner        = local.gcp_label_owner
  }
  # org.cost_center / org.owner (defaults platform / platform-team, as in the
  # AWS roots) in label form: lowercase letters, digits, '_' and '-', at most
  # 63 characters. Any other character becomes '-'.
  gcp_label_cost_center = substr(replace(lower(coalesce(local.cfg.cost_center, "platform")), "/[^a-z0-9_-]/", "-"), 0, 63)
  gcp_label_owner       = substr(replace(lower(coalesce(local.cfg.owner, "platform-team")), "/[^a-z0-9_-]/", "-"), 0, 63)
}
