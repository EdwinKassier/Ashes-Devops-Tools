# Plan assertions for the supabase/vault-secrets module: verify the reconcile
# provisioner is planned and its triggers hash the desired state (non-sensitive), so
# a change to secrets/URL re-runs reconciliation (audit rule: no raw sensitive values
# in triggers). All runs use mock_provider so no database is required.

mock_provider "null" {}

variables {
  postgres_url = "postgresql://postgres.abcdefghijklmnopqrst:password@aws-0-eu-west-2.pooler.supabase.com:5432/postgres"
  secrets      = { XERO_CLIENT_ID = "mock-id" }
}

run "reconcile_triggers_hash_desired_state" {
  command = plan

  assert {
    condition     = null_resource.reconcile.triggers["desired_hash"] == nonsensitive(sha256(jsonencode(var.secrets)))
    error_message = "reconcile trigger must hash the desired secrets map so changes re-run reconciliation."
  }

  assert {
    condition     = null_resource.reconcile.triggers["reconcile_hash"] != ""
    error_message = "reconcile trigger must include the reconcile script hash."
  }

  assert {
    condition     = can(null_resource.bootstrap.triggers)
    error_message = "A bootstrap provisioner must be planned."
  }
}
