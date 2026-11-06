# Impersonation is OPTIONAL: leave terraform_admin_email null in TFC —
# dynamic credentials already run plan as <prefix>-projects-plan and apply as
# <prefix>-projects-apply. Set it only for a deliberate local human run.
provider "google" {
  region                      = local.default_region
  impersonate_service_account = var.terraform_admin_email
  default_labels              = local.gcp_default_labels
}

provider "google-beta" {
  region                      = local.default_region
  impersonate_service_account = var.terraform_admin_email
  default_labels              = local.gcp_default_labels
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
