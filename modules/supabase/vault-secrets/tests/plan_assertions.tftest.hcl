# Plan assertions for the supabase/vault-secrets module: verify the provisioner
# resources are planned as built-in terraform_data, and that their triggers carry
# no recoverable secret material:
#   - the DB identity digest is computed over the URL with the password stripped;
#   - the desired-state digest is keyed with the DB password (not a bare sha256 of
#     the secrets map), so it cannot be brute-forced from state alone.
# command = plan only — provisioners never run and no database is required.

variables {
  postgres_url = "postgresql://postgres.abcdefghijklmnopqrst:password@aws-0-eu-west-2.pooler.supabase.com:5432/postgres"
  secrets      = { XERO_CLIENT_ID = "mock-id" }
}

run "reconcile_triggers_hash_desired_state" {
  command = plan

  assert {
    condition     = terraform_data.reconcile.triggers_replace["desired_hash"] == nonsensitive(sha256(join("\n", ["vault-secrets/desired/v2", var.postgres_url, jsonencode(var.secrets)])))
    error_message = "reconcile trigger must hash the desired secrets map (keyed with the DB URL) so changes re-run reconciliation."
  }

  assert {
    condition     = terraform_data.reconcile.triggers_replace["desired_hash"] != nonsensitive(sha256(jsonencode(var.secrets)))
    error_message = "reconcile trigger must NOT be a bare (unkeyed) sha256 of the secrets map — that is brute-forceable from state."
  }

  assert {
    condition     = terraform_data.reconcile.triggers_replace["reconcile_hash"] != ""
    error_message = "reconcile trigger must include the reconcile script hash."
  }

  assert {
    condition     = can(terraform_data.bootstrap.triggers_replace)
    error_message = "A bootstrap provisioner must be planned."
  }
}

run "db_identity_excludes_password" {
  command = plan

  # The DB identity digest must equal the digest of the password-stripped URL,
  # and must not equal the digest of the full URL (which would embed the secret).
  assert {
    condition     = terraform_data.bootstrap.triggers_replace["db"] == sha256("postgresql://postgres.abcdefghijklmnopqrst@aws-0-eu-west-2.pooler.supabase.com:5432/postgres")
    error_message = "bootstrap db trigger must hash the postgres URL with the password stripped."
  }

  assert {
    condition     = terraform_data.bootstrap.triggers_replace["db"] != nonsensitive(sha256(var.postgres_url))
    error_message = "bootstrap db trigger must not be a sha256 of the full URL (it contains the password)."
  }

  assert {
    condition     = terraform_data.reconcile.triggers_replace["db"] == terraform_data.bootstrap.triggers_replace["db"]
    error_message = "bootstrap and reconcile must key on the same DB identity."
  }
}

run "password_rotation_does_not_change_db_identity" {
  command = plan

  variables {
    postgres_url = "postgresql://postgres.abcdefghijklmnopqrst:rotated-Pa55word@aws-0-eu-west-2.pooler.supabase.com:5432/postgres"
  }

  assert {
    condition     = terraform_data.bootstrap.triggers_replace["db"] == sha256("postgresql://postgres.abcdefghijklmnopqrst@aws-0-eu-west-2.pooler.supabase.com:5432/postgres")
    error_message = "rotating only the DB password must not change the bootstrap DB identity trigger."
  }
}

run "every_script_run_installs_dependencies_first" {
  command = plan

  # A remote runner starts each run without node_modules, so the install must
  # happen in the same command as each script, before node, and stay hardened.
  assert {
    condition     = local.bootstrap_command == "npm ci --ignore-scripts --no-audit --no-fund --prefix ${path.module}/scripts && node ${path.module}/scripts/bootstrap.mjs"
    error_message = "bootstrap must run npm ci --ignore-scripts in the same command, before node."
  }

  assert {
    condition     = local.reconcile_command == "npm ci --ignore-scripts --no-audit --no-fund --prefix ${path.module}/scripts && node ${path.module}/scripts/reconcile.mjs"
    error_message = "reconcile must run npm ci --ignore-scripts in the same command, before node."
  }
}
