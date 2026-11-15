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
    condition     = local.bootstrap_command == "${local.npm_install_command} && node ${path.module}/scripts/bootstrap.mjs"
    error_message = "bootstrap must run the npm install in the same command, before node."
  }

  assert {
    condition     = local.reconcile_command == "${local.npm_install_command} && node ${path.module}/scripts/reconcile.mjs"
    error_message = "reconcile must run the npm install in the same command, before node."
  }

  assert {
    condition     = endswith(local.npm_install_command, " npm ci --ignore-scripts --no-audit --no-fund --prefix ${path.module}/scripts")
    error_message = "the install must stay npm ci --ignore-scripts --no-audit --no-fund on the module's scripts directory."
  }
}

# The provisioner environment (POSTGRES_URL, VAULT_DESIRED_JSON,
# SUPABASE_SSL_CERT) and the workspace's own variables (SUPABASE_ACCESS_TOKEN)
# must reach node, never npm: npm, its config files and its registry would see
# them. env -i clears the environment for npm only and passes back the
# variables npm needs, each one only when it is set.
run "npm_install_sees_no_secret_environment" {
  command = plan

  assert {
    condition = local.npm_install_command == join(" ", [
      "env -i",
      "$${PATH:+\"PATH=$${PATH}\"}",
      "$${HOME:+\"HOME=$${HOME}\"}",
      "$${TMPDIR:+\"TMPDIR=$${TMPDIR}\"}",
      "$${npm_config_cache:+\"npm_config_cache=$${npm_config_cache}\"}",
      "$${NPM_CONFIG_CACHE:+\"NPM_CONFIG_CACHE=$${NPM_CONFIG_CACHE}\"}",
      "$${HTTP_PROXY:+\"HTTP_PROXY=$${HTTP_PROXY}\"}",
      "$${HTTPS_PROXY:+\"HTTPS_PROXY=$${HTTPS_PROXY}\"}",
      "$${NO_PROXY:+\"NO_PROXY=$${NO_PROXY}\"}",
      "$${http_proxy:+\"http_proxy=$${http_proxy}\"}",
      "$${https_proxy:+\"https_proxy=$${https_proxy}\"}",
      "$${no_proxy:+\"no_proxy=$${no_proxy}\"}",
      "$${NODE_EXTRA_CA_CERTS:+\"NODE_EXTRA_CA_CERTS=$${NODE_EXTRA_CA_CERTS}\"}",
      "npm ci --ignore-scripts --no-audit --no-fund --prefix ${path.module}/scripts",
    ])
    error_message = "npm ci must run under env -i with only PATH, HOME, TMPDIR, the npm cache, the proxy variables and NODE_EXTRA_CA_CERTS passed back."
  }

  assert {
    condition = alltrue([
      for secret in ["POSTGRES_URL", "VAULT_DESIRED_JSON", "SUPABASE_SSL_CERT", "SUPABASE_ACCESS_TOKEN", "VERCEL_API_TOKEN", "TFE_TOKEN", "VAULT_ALLOW_EMPTY_DESIRED"] :
      !strcontains(local.npm_install_command, secret)
    ])
    error_message = "no provisioner or workspace secret may be passed to npm."
  }

  assert {
    condition = alltrue([
      for c in [local.bootstrap_command, local.reconcile_command] :
      length(split(" && ", c)) == 2 && startswith(split(" && ", c)[1], "node ")
    ])
    error_message = "node must still run with the full provisioner environment (no env -i before node)."
  }
}
