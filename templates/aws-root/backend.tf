# CLONE-ME: replace REPLACE_ME below with the real workspace name for this root.
#   - Fixed foundational roots use `workspaces { name = "aws-security" }` (one workspace).
#   - Per-env workload roots use `workspaces { prefix = "aws-workload-" }` and select the
#     environment via TF_WORKSPACE (e.g. TF_WORKSPACE=aws-workload-dev). Swap the `name`
#     line for a `prefix` line in that case.
#
# The TFC organization is NOT hard-coded here — it comes from backend.hcl or
# TF_CLI_ARGS_init so the same root works across orgs and CI without edits
# (matches envs/organization/backend.tf).
terraform {
  backend "cloud" {
    # Supply organization via TF_CLI_ARGS_init or a gitignored backend.hcl:
    #   export TF_CLI_ARGS_init="-backend-config=organization=<your-tfc-org>"
    # or create backend.hcl with: organization = "<your-tfc-org>"
    # and run: terraform init -backend-config=backend.hcl

    workspaces {
      name = "REPLACE_ME"
    }
  }
}
