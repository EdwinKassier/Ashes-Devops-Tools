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
  }
}
