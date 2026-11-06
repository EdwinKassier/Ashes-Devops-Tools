# HCP Terraform OPA policy set (attached by envs/tfc-admin when
# enable_policy_sets = true; policies_path = "policies/opa").
#
# Each block names a query whose result must be an array/set: empty = pass.
# A query may evaluate code from several .rego files (shared helpers live in
# lib_helpers.rego, package terraform.lib). *_test.rego files are unit tests
# for `opa test`; they define no policy and are never queried.
#
# enforcement_level:
#   mandatory - a violation stops the run (users with "Manage Policy
#               Overrides" can override, because the set is overridable)
#   advisory  - a violation is reported on the run but never blocks it
#
# Mandatory policies encode controls every module in this repo already
# satisfies by default (verified by the module tests); advisory policies are
# heuristics or hygiene. Full guide: docs/architecture/policy-as-code.md.

# ── Mandatory: public exposure ──────────────────────────────────────────────
policy "gcs_no_public_buckets" {
  query             = "data.terraform.policies.gcs_no_public_buckets.deny"
  enforcement_level = "mandatory"
}

policy "gcp_iam_no_public_members" {
  query             = "data.terraform.policies.gcp_iam_no_public_members.deny"
  enforcement_level = "mandatory"
}

policy "aws_s3_public_access" {
  query             = "data.terraform.policies.aws_s3_public_access.deny"
  enforcement_level = "mandatory"
}

policy "aws_sg_no_public_admin_ports" {
  query             = "data.terraform.policies.aws_sg_no_public_admin_ports.deny"
  enforcement_level = "mandatory"
}

# ── Mandatory: identity and encryption ─────────────────────────────────────
policy "aws_iam_no_admin_wildcard" {
  query             = "data.terraform.policies.aws_iam_no_admin_wildcard.deny"
  enforcement_level = "mandatory"
}

policy "aws_kms_key_rotation" {
  query             = "data.terraform.policies.aws_kms_key_rotation.deny"
  enforcement_level = "mandatory"
}

policy "database_private_encrypted" {
  query             = "data.terraform.policies.database_private_encrypted.deny"
  enforcement_level = "mandatory"
}

# ── Advisory ────────────────────────────────────────────────────────────────
policy "aws_s3_bucket_public_access_block_present" {
  query             = "data.terraform.policies.aws_s3_public_access.warn"
  enforcement_level = "advisory"
}

policy "require_labels" {
  query             = "data.terraform.policies.require_labels.deny"
  enforcement_level = "advisory"
}

policy "destroy_guard" {
  query             = "data.terraform.policies.destroy_guard.deny"
  enforcement_level = "advisory"
}
