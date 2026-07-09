# SCAFFOLD — this is a cloneable AWS root, not a live root. Clone the whole
# templates/aws-root/ directory to envs/<cloud>-<layer>/ (e.g. envs/aws-security),
# set the workspace name in backend.tf, uncomment the blocks below, and wire the
# stage module for this layer. See docs/architecture/adding-a-cloud.md.
#
# Convention 5 — credential-free remote state:
# Every terraform_remote_state uses backend = "cloud" + config = { organization,
# workspaces = { name } }. This resolves at plan time, so the root passes
# `terraform validate` with `-backend=false` and NO cloud credentials. Keep this
# block COMMENTED in the scaffold so `terraform validate` succeeds bare.
#
# data "terraform_remote_state" "aws_organization" {
#   backend = "cloud"
#   config = {
#     organization = var.tfc_organization
#     workspaces = {
#       name = "aws-organization"
#     }
#   }
# }

# Wire the stage module for this layer. Role ARNs, account IDs, and other
# cross-root inputs come from the remote state above (never hard-coded).
#
# module "workload" {
#   source = "../../modules/stages/aws-workload"
#
#   aws_region          = var.aws_region
#   aws_enabled_regions = var.aws_enabled_regions
#   # account_role_arn  = data.terraform_remote_state.aws_organization.outputs.account_role_arns["workload"]
# }
