# SCAFFOLD — provider-agnostic cloneable root. This is the CONTRACT a new cloud
# (Azure, etc.) follows; templates/aws-root/ is the concrete aws instance of it.
# Clone to envs/<cloud>-<layer>/, fill in versions.tf + providers.tf for your
# cloud, set the workspace in backend.tf, and wire the stage module below.
# See docs/architecture/adding-a-cloud.md.
#
# Convention 5 — credential-free remote state:
# Every terraform_remote_state uses backend = "cloud" + config = { organization,
# workspaces = { name } }. This resolves at plan time, so the root passes
# `terraform validate` with `-backend=false` and NO cloud credentials. Keep this
# block COMMENTED in the scaffold so `terraform validate` succeeds bare.
#
# data "terraform_remote_state" "cloud_organization" {
#   backend = "cloud"
#   config = {
#     organization = var.tfc_organization
#     workspaces = {
#       name = "<cloud>-organization"
#     }
#   }
# }

# Wire the stage module for this layer. Cross-root inputs (role ARNs, account /
# subscription IDs) come from the remote state above — never hard-coded.
#
# module "stage" {
#   source = "../../modules/stages/<cloud>-<layer>"
# }
