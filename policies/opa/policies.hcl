# HCP Terraform OPA policy set (attached by envs/tfc-admin when
# enable_policy_sets = true; policies_path = "policies/opa").
#
# Each block names a query whose result must be an array/set: empty = pass.
# A query may evaluate code from several .rego files (shared helpers live in
# lib_helpers.rego, package terraform.lib). *_test.rego files are unit tests
# for `opa test`; they define no policy and are never queried.
#
# enforcement_level:
#   mandatory - a violation stops the run. tfc-admin creates the set with
#               overridable = false (policy_set_overridable), so not even a
#               user with "Manage Policy Overrides" can wave it through
#   advisory  - a violation is reported on the run but never blocks it
#
# Mandatory policies encode controls every module in this repo already
# satisfies by default (verified by the module tests); advisory policies are
# heuristics or hygiene. The destroy guard is a separate, overridable set in
# policies/opa-destructive. Full guide: docs/architecture/policy-as-code.md.

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

policy "aws_iam_federated_trust_pinned" {
  query             = "data.terraform.policies.aws_iam_federated_trust_pinned.deny"
  enforcement_level = "mandatory"
}

policy "gcp_no_basic_roles_high_scope" {
  query             = "data.terraform.policies.gcp_no_basic_roles_high_scope.deny"
  enforcement_level = "mandatory"
}

policy "gcp_cloud_run_no_public_url" {
  query             = "data.terraform.policies.gcp_cloud_run_no_public_url.deny"
  enforcement_level = "mandatory"
}

# A workload identity principalSet must pin one repository and a ref or
# environment: no whole pool, owner, repository name or bare ref.
policy "gcp_wif_principalset_pinned" {
  query             = "data.terraform.policies.gcp_wif_principalset_pinned.deny"
  enforcement_level = "mandatory"
}

# ── Mandatory: plan-time code execution ─────────────────────────────────────
# No provisioners outside envs/saas -> saas_workload -> vault_secrets (exact
# call chain and sources), no data "external" / data "http", only allowlisted
# providers, no provider endpoint / proxy / TLS overrides. Evaluated after the
# plan: it stops the apply and detects, but does not prevent, plan-time code.
policy "no_plan_time_code_execution" {
  query             = "data.terraform.policies.no_plan_time_code_execution.deny"
  enforcement_level = "mandatory"
}

# ── Mandatory: reviewed code only on the control plane ─────────────────────
# A run that can apply on a VCS-connected workspace tagged layer:control-plane,
# layer:bootstrap or tier:production must carry a commit SHA (it came from the
# connected repository, not an API-uploaded configuration version). PREVIEW:
# the run field is confirmed by the docs only (docs/known-gaps.md).
policy "tfc_vcs_run_only" {
  query             = "data.terraform.policies.tfc_vcs_run_only.deny"
  enforcement_level = "mandatory"
}

# ── Mandatory: ownership and cost labels ────────────────────────────────────
# Ownership and cost keys on listed taggable types: GCP managed-by,
# environment, cost-center, owner; AWS ManagedBy, Environment, CostCenter,
# Owner. Every root writes them through provider default_labels / default_tags.
policy "require_labels" {
  query             = "data.terraform.policies.require_labels.deny"
  enforcement_level = "mandatory"
}

# ── Advisory ────────────────────────────────────────────────────────────────
policy "aws_s3_bucket_public_access_block_present" {
  query             = "data.terraform.policies.aws_s3_public_access.warn"
  enforcement_level = "advisory"
}

policy "aws_iam_federated_trust_unknown" {
  query             = "data.terraform.policies.aws_iam_federated_trust_pinned.federated_unknown"
  enforcement_level = "advisory"
}

policy "gcp_wif_principalset_repo_wide" {
  query             = "data.terraform.policies.gcp_wif_principalset_pinned.repo_wide"
  enforcement_level = "advisory"
}
