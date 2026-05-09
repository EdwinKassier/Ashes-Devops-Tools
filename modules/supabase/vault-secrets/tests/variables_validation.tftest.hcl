# Variable validation tests for modules/supabase/vault-secrets.
# The null provider mock prevents provisioners from running.

mock_provider "null" {}

variables {
  postgres_url = "postgresql://postgres.abcdefghijklmnopqrst:password@aws-0-eu-west-2.pooler.supabase.com:5432/postgres"
  secrets      = { XERO_CLIENT_ID = "mock-id" }
}

run "valid_inputs_accepted" {
  command = plan
}

run "empty_secrets_map_passes_variable_validation" {
  # Variable validation does NOT reject an empty secrets map — there is no
  # Terraform validation rule requiring at least one secret.
  # The runtime safety guard in reconcile.mjs (VAULT_ALLOW_EMPTY_DESIRED) is what
  # prevents accidental vault wipeout; that fires at apply time, not at plan time.
  command = plan
  variables { secrets = {} }
}
