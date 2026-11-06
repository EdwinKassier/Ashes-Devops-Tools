# CLONE-ME: replace REPLACE_ME below with the real workspace name for this root.
#   - Fixed foundational roots use `workspaces { name = "aws-security" }`.
#   - Per-env roots use `workspaces { tags = ["cloud:aws", "layer:workload"] }`
#     and select the environment by full name via TF_WORKSPACE
#     (e.g. TF_WORKSPACE=aws-workload-dev). Swap the `name` line for `tags`.
#
# The TFC organization is NOT hard-coded here, so the same root works across
# orgs and CI without edits. The `cloud` block takes no -backend-config; export
#   TF_CLOUD_ORGANIZATION=<your-tfc-org>
#   TF_CLOUD_HOSTNAME=app.terraform.io   # optional; set for HCP EU / TFE
# before `terraform init`. `make backend-check` proves the block initialises.
terraform {
  cloud {
    workspaces {
      name = "REPLACE_ME"
    }
  }
}
