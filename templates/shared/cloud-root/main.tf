# SCAFFOLD — provider-agnostic cloneable root. This is the CONTRACT a new cloud
# (Azure, etc.) follows; templates/aws/root/ is the concrete aws instance of it.
# Clone to envs/<cloud>/<layer>/, fill in versions.tf + providers.tf for your
# cloud, set the workspace in backend.tf and local.cloud_key in config.tf, and
# wire the stage module below. See docs/architecture/adding-a-cloud.md.
#
# Root conventions this scaffold already carries:
#   * config.tf           — config/landing-zone.yaml single-source config
#   * contract-gated read — below
#   * tests/              — plan suites (run in CI from templates/)

# ── Contract-gated remote state (FAST-style stage contract override) ──────────
# The upstream contract comes from, in order:
#   1. var.organization_contract (tfvars / TFC variable),
#   2. <cloud>.contracts.organization in config/landing-zone.yaml,
#   3. the <cloud>-organization workspace's remote state.
# The remote-state read happens ONLY when no contract was supplied (count = 0
# otherwise), so the root plans without the upstream workspace.
#
# Convention 5 — credential-free remote state: backend = "cloud" + config =
# { organization, workspaces = { name } } resolves at plan time, so the root
# passes `terraform validate -backend=false` with NO cloud credentials.
locals {
  organization_contract = var.organization_contract != null ? var.organization_contract : local.cfg.organization_contract
  read_organization     = local.organization_contract == null
}

data "terraform_remote_state" "cloud_organization" {
  count   = local.read_organization ? 1 : 0
  backend = "cloud"
  config = {
    organization = local.tfc_organization
    workspaces   = { name = var.organization_workspace_name }
  }
}

locals {
  # No try(): a renamed upstream output must fail the plan, not degrade silently.
  # CLONE-ME: replace `contract` with the upstream output(s) this root consumes.
  upstream = local.read_organization ? data.terraform_remote_state.cloud_organization[0].outputs.contract : local.organization_contract
}

# Wire the stage module for this layer. Cross-root inputs (role ARNs, account /
# subscription IDs) come from local.upstream above — never hard-coded.
#
# module "stage" {
#   source = "../../../modules/<cloud>/stages/<layer>" # envs/<cloud>/<layer> -> repo root
# }
