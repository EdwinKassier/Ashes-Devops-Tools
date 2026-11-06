# SCAFFOLD — this is a cloneable AWS root, not a live root. Clone the whole
# templates/aws/root/ directory to envs/aws/<layer>/ (e.g. envs/aws/security),
# set the workspace name in backend.tf, and wire the stage module for this
# layer. See docs/architecture/adding-a-cloud.md.
#
# Root conventions this scaffold already carries:
#   * config.tf           — config/landing-zone.yaml single-source config
#   * contract-gated read — below
#   * tests/              — mock_provider suites (run in CI from templates/)

# ── Contract-gated remote state (FAST-style stage contract override) ──────────
# The upstream contract comes from, in order:
#   1. var.organization_contract (tfvars / TFC variable),
#   2. aws.contracts.organization in config/landing-zone.yaml,
#   3. the aws-organization workspace's remote state.
# The remote-state read happens ONLY when no contract was supplied (count = 0
# otherwise), so the root plans without the upstream workspace (tests, fresh
# environments, out-of-band org).
#
# Convention 5 — credential-free remote state: backend = "cloud" + config =
# { organization, workspaces = { name } } resolves at plan time, so the root
# passes `terraform validate -backend=false` with NO cloud credentials.
locals {
  organization_contract = var.organization_contract != null ? var.organization_contract : local.cfg.organization_contract
  read_organization     = local.organization_contract == null
}

data "terraform_remote_state" "aws_organization" {
  count   = local.read_organization ? 1 : 0
  backend = "cloud"
  config = {
    organization = local.tfc_organization
    workspaces   = { name = var.organization_workspace_name }
  }
}

locals {
  # No try(): a renamed upstream output must fail the plan, not degrade silently.
  account_ids = local.read_organization ? data.terraform_remote_state.aws_organization[0].outputs.account_ids : local.organization_contract.account_ids
}

# Wire the stage module for this layer. Account IDs, role ARNs and other
# cross-root inputs come from the contract above (never hard-coded).
#
# module "workload" {
#   source = "../../../modules/aws/stages/workload" # envs/aws/<layer> -> repo root
#
#   aws_region          = local.aws_region
#   aws_enabled_regions = local.aws_enabled_regions
#   account_id          = local.account_ids["workload"]
# }
