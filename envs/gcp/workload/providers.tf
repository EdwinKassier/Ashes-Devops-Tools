# Impersonation is OPTIONAL. Leave terraform_admin_email null in
# Terraform Cloud: dynamic credentials already authenticate plan as
# <prefix>-wl-<env>-plan and apply as <prefix>-wl-<env>-apply, and a null
# impersonate_service_account means "use the ambient credentials". A plan SA
# cannot impersonate the admin SA, so setting it on a TFC workspace now fails
# closed. Set it only for a deliberate local human run.
provider "google" {
  region                      = local.region
  impersonate_service_account = var.terraform_admin_email
  default_labels              = local.gcp_default_labels
}

provider "google-beta" {
  region                      = local.region
  impersonate_service_account = var.terraform_admin_email
  default_labels              = local.gcp_default_labels
}

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
    workspace    = "gcp-workload-${var.environment}"
    environment  = var.environment
  }
}

# tfe serves only the opt-in SaaS secret bridge (ephemeral "tfe_outputs" "saas").
# Terraform configures a declared provider even when nothing uses it, and tfe
# refuses to configure without a token, so a workspace with the bridge off gets
# an inert placeholder (NOT a secret, and it grants nothing: on configure the
# provider only calls the host's discovery and ping endpoints, which need no
# valid token). With the bridge on, token = null reads TFE_TOKEN: the
# saas-outputs-reader team token.
provider "tfe" {
  token = var.enable_saas_secret_bridge ? null : "saas-bridge-disabled-placeholder"
}
