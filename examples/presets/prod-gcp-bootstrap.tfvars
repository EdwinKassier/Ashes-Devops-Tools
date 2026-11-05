# Production hardening overlay for envs/gcp/bootstrap. Apply IN ADDITION to your own tfvars:
#   terraform -chdir=envs/gcp/bootstrap plan -var-file=your.tfvars -var-file=../../../examples/presets/prod-gcp-bootstrap.tfvars
#
# Per-stage plan/apply service accounts with run-phase-scoped WIF bindings are now
# the default (audit C2), so the old enable_privilege_split toggle is gone.
#
# Keep the GitHub Actions -> GCP federation pool OFF unless a workflow needs it.
# When enabled it is bound only to the read-only organization-plan SA, pinned to
# the immutable repository_id / repository_owner_id.
enable_github_wif = false
