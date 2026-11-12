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
# LandingZone, Workspace, Environment), in GCP label form (lowercase keys and
# values, hyphens). Values are plan-known and label-valid (project_prefix and
# environment are validated lowercase), so there is no perpetual diff. The
# provider MERGES these into each resource's effective labels: a module-level
# `labels` entry with the same key wins, so modules never fight the provider.
locals {
  gcp_default_labels = {
    managed-by   = "terraform"
    landing-zone = local.project_prefix
    workspace    = "gcp-projects"
    environment  = "shared"
  }
}
