# Impersonation is OPTIONAL. Leave terraform_admin_email null in
# Terraform Cloud: dynamic credentials already authenticate plan as
# <prefix>-network-hub-plan and apply as <prefix>-network-hub-apply, and a null
# impersonate_service_account means "use the ambient credentials". A plan SA
# cannot impersonate the admin SA, so setting it on a TFC workspace now fails
# closed. Set it only for a deliberate local human run.
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
    workspace    = "gcp-network-hub"
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
