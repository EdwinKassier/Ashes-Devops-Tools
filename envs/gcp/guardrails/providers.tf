# Ambient credentials only. In HCP Terraform, dynamic credentials authenticate
# plan as <prefix>-guardrails-plan and apply as <prefix>-guardrails-apply (the
# only automation identity holding roles/iam.denyAdmin). gcp-bootstrap binds both
# to this workspace by its immutable ID. There is deliberately no impersonation
# input: the break-glass path is a PAM-elevated guardrail_owner_members member
# applying deny_policy_specs with gcloud (docs/runbooks/break-glass.md).
provider "google" {
  default_labels = local.gcp_default_labels
}

# Canonical label set (see envs/gcp/organization/providers.tf). IAM deny policies
# take no labels; kept so every GCP root writes the same provider defaults.
locals {
  gcp_default_labels = {
    managed-by   = "terraform"
    landing-zone = local.project_prefix
    workspace    = "gcp-guardrails"
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
