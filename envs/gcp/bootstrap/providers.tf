# Impersonation is OPTIONAL. In Terraform Cloud leave
# terraform_admin_email unset: dynamic credentials already authenticate the run as
# the phase-specific SA (plan -> <prefix>-bootstrap-plan, apply -> terraform-admin),
# and a null impersonate_service_account means "use the ambient credentials".
# Set it only for a local human re-apply (phase-0 first apply: leave it null and
# run as your own admin credentials while the SA is created).
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
    workspace    = "gcp-bootstrap"
    environment  = "shared"
  }
}
