# HCP Terraform OPA policy set (attached by envs/tfc-admin when
# enable_policy_sets = true). Each policy's query points at its .rego file in
# this directory (the file name must equal the policy name). Every policy
# starts ADVISORY: a violation is reported on the run but does not block it.
# Promote one to "mandatory" only after it has run clean across the estate.

policy "gcs_no_public_buckets" {
  query             = "data.terraform.policies.gcs_no_public_buckets.deny"
  enforcement_level = "advisory"
}

policy "require_labels" {
  query             = "data.terraform.policies.require_labels.deny"
  enforcement_level = "advisory"
}
