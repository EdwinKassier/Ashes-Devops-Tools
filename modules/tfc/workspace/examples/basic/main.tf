# Basic working example for the tfc/workspace module.
# Creates one VCS-driven Terraform Cloud workspace for a control-plane root:
# manual apply (the default), no speculative plans on pull requests and no
# destroy plans from the UI, state shared with no other workspace, run triggers
# scoped to the root plus the module domain it consumes, TFC dynamic (OIDC)
# credentials instead of static keys, and an email notification on failed or
# waiting runs. Run `terraform init && terraform validate` here to check it.
#
# envs/tfc-admin derives the real workspace set from config/landing-zone.yaml.
# The organization, project, GitHub App installation and user IDs below are
# placeholders: replace them with your own. Never put a secret in `variables`
# without `sensitive = true` (sensitive values are written write-only).

provider "tfe" {
  # Reads TFE_TOKEN from the environment.
  organization = "example-org"
}

module "workspace" {
  source = "../../"

  name              = "gcp-organization"
  organization      = "example-org"
  description       = "GCP control plane: folders, org policies, KMS, audit, billing."
  working_directory = "envs/gcp/organization"
  project_id        = "prj-AbCdEfGhIjKlMnOp"
  terraform_version = "~> 1.17"
  tag_names         = ["cloud:gcp", "layer:control-plane"]

  trigger_patterns = [
    "envs/gcp/organization/**",
    "modules/gcp/**",
    "config/landing-zone.yaml",
  ]

  vcs_repo = {
    identifier                 = "example-org/landing-zone"
    branch                     = "main"
    github_app_installation_id = "ghain-AbCdEfGhIjKlMnOp"
  }

  # Control-plane hardening: no privileged plans for untrusted PRs, no UI destroys.
  speculative_enabled = false
  allow_destroy_plan  = false

  variables = {
    TFC_GCP_PROVIDER_AUTH = {
      value    = "true"
      category = "env"
    }
    TFC_GCP_WORKLOAD_PROVIDER_NAME = {
      value    = "projects/123456789012/locations/global/workloadIdentityPools/tfc/providers/tfc"
      category = "env"
    }
  }

  notifications = {
    platform-oncall = {
      destination_type = "email"
      email_user_ids   = ["user-AbCdEfGhIjKlMnOp"]
    }
  }
}
