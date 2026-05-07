# ──────────────────────────────────────────────────────────────────────────────
# envs/apps — development environment tfvars
#
# Usage:
#   terraform -chdir=envs/apps plan -var-file=examples/dev.tfvars
#   make plan-apps APP_ENV=dev APP_VARS=examples/dev.tfvars
#
# Copy this file and adjust values for staging/production environments.
# Never commit secrets or real billing account IDs to version control.
# ──────────────────────────────────────────────────────────────────────────────

# ── Project & identity ─────────────────────────────────────────────────────────

project_prefix  = "ashes"
environment     = "dev"
provider_region = "europe-west1"

# Service account that Terraform impersonates (created by bootstrap).
# Format: terraform@{admin-project-id}.iam.gserviceaccount.com
terraform_admin_email = "terraform@ashes-admin-xxxx.iam.gserviceaccount.com"

# Terraform Cloud configuration
tfc_organization            = "your-tfc-org-name"
organization_workspace_name = "organization"

# ── Networking ─────────────────────────────────────────────────────────────────
#
# NOTE: vpc_cidr_block is NOT a variable here — it is read from the organization
# workspace remote state via local.env_config.cidr_block (set in the environments
# map in terraform.tfvars.example for envs/organization).
# Set the CIDR there, not here.

# VPC Flow Logs
log_config_flow_sampling        = 0.5
log_config_aggregation_interval = "INTERVAL_5_SEC"
vpc_flow_logs_retention_days    = 30

# ── Security features (off by default in dev, on in prod) ─────────────────────

enable_deletion_protection = false # set true in production
enable_cloud_armor         = false # set true when attaching an external LB
enable_owasp_rules         = false
enable_adaptive_protection = false
owasp_sensitivity          = 2

# ── VPC Service Controls (optional — start in dry-run) ────────────────────────

# Uncomment and configure to enable VPC-SC for this environment.
# vpc_sc_enable_dry_run      = true
# vpc_sc_perimeter_title     = "Dev Perimeter"
# vpc_sc_restricted_services = ["storage.googleapis.com", "bigquery.googleapis.com"]
# vpc_sc_ingress_policies    = []
# vpc_sc_egress_policies     = []

# ── Budgets ───────────────────────────────────────────────────────────────────

monthly_budget_limit = 500
budget_currency      = "USD"

# ── Labels ────────────────────────────────────────────────────────────────────

extra_labels = {
  cost-centre = "platform"
  owner       = "platform-team"
}
