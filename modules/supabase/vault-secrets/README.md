# Supabase Vault Secrets Module

Bootstraps the Supabase Vault with helper functions and reconciles a desired-state map of secrets.

## Runtime Requirements

- **Node.js >= 18** must be in the execution environment's `PATH`.
- **`SUPABASE_ACCESS_TOKEN`** (env var) — required in CI to use the Management API path, which bypasses the Supavisor pooler and avoids the common _"Tenant or user not found"_ error on GitHub Actions runners.
- **`SUPABASE_SSL_CERT`** (base64-encoded CA bundle) — required for `*.pooler.supabase.com` connections. Fetch from the Supabase dashboard → Project Settings → Database → SSL Certificate.

## Script dependencies

Installed **automatically** at apply time by `terraform_data.npm_install`:

```bash
npm ci --ignore-scripts --no-audit --no-fund --prefix modules/supabase/vault-secrets/scripts
```

`npm ci` installs exactly the committed `package-lock.json` (integrity-checked); `--ignore-scripts` means no dependency lifecycle script ever runs on the apply runner (`pg` and its dependencies are pure JavaScript and need none). The runner needs Node.js 18+ and npm on `PATH` plus registry access. To prime locally, run the same command.

## Database objects and privileges

`bootstrap.mjs` creates two `SECURITY DEFINER` helpers in the private schema **`iac_vault`**:

| Function | Purpose |
|----------|---------|
| `iac_vault.upsert_vault_secret(name, value, description)` | create or update an IaC-managed secret |
| `iac_vault.delete_vault_secret(name)` | delete an IaC-managed secret (orphan sweep) |

Hardening:

- **Not API-exposed.** `iac_vault` is not in PostgREST's exposed schemas, so `/rest/v1/rpc/...` cannot reach the helpers with any API key. **Never add `iac_vault` to the project's exposed schemas** (`supabase_db_schema`; the settings module rejects it).
- **Explicit revokes.** `EXECUTE` and schema `USAGE` are revoked from `PUBLIC`, `anon` and `authenticated`. Supabase grants `anon`/`authenticated` directly through default privileges, so revoking from `PUBLIC` alone is not enough. Only `service_role` and the owning role can call the helpers.
- **`SET search_path = ''`** with schema-qualified references (`vault.secrets`, `vault.create_secret`, `pg_catalog` operators), so a caller cannot hijack name resolution.
- **Namespace-restricted.** Both helpers raise `insufficient_privilege` for any name outside `^[A-Z][A-Z0-9_]*$`, so they cannot read-modify or delete runtime-managed entries.

The reconcile script calls the helpers over a direct `pg` connection or the Supabase Management API, never PostgREST.

### Upgrading from the `public.*` helpers (breaking change)

Earlier versions created `public.upsert_vault_secret`, `public.delete_vault_secret` and `public.delete_vault_secrets_by_prefix`. Supabase's default privileges made those callable with the **public anon key**, so any visitor could overwrite or delete vault secrets. On the next apply, bootstrap **drops** all three. Application code that called them over RPC must ship its own reviewed helpers for runtime-managed (non-IaC) secrets. If you could not upgrade immediately, check exposure with:

```sql
select p.proname, has_function_privilege('anon', p.oid, 'EXECUTE')
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname like '%vault_secret%';
```

The provisioner resources moved from `null_resource` to built-in `terraform_data`. `moved` blocks migrate existing state in place (`npm_install` is not re-run). `bootstrap` and `reconcile` run once on upgrade because their scripts and trigger inputs changed, which applies the privilege migration above.

## Trigger hashing

Triggers must not hold sensitive values, and a bare `sha256` of a low-entropy secret can be brute-forced from state. So:

- `db` hashes the postgres URL **with the password stripped**. Rotating only the DB password does not re-run bootstrap.
- `desired_hash` must change whenever a secret value changes, so it is keyed with the DB URL (including its high-entropy password, which is not in this module's state): `sha256("vault-secrets/desired/v2" \n postgres_url \n jsonencode(secrets))`. Rotating the DB password re-runs reconcile once, which is harmless because reconcile is idempotent.

## IaC Namespace

Only secrets whose names match `^[A-Z][A-Z0-9_]*$` (UPPER_SNAKE_CASE) are managed. Lowercase and mixed-case names (runtime-managed per-tenant entries) are never touched.

## Safety Guard

If `var.secrets` is empty and the vault already contains entries, the reconcile script **refuses to apply** to prevent accidental data loss. Set `VAULT_ALLOW_EMPTY_DESIRED=1` in the environment to override.

## Destroy Behaviour

`terraform destroy` removes the `terraform_data` records from Terraform state but does **not** wipe the Supabase Vault contents. Vault secrets persist after destroy. To remove vault secrets, set `secrets = {}` and apply (using `VAULT_ALLOW_EMPTY_DESIRED=1` if the vault already has entries) before destroying.

<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	postgres_url =
	secrets =
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.17, < 2.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |



## Resources

The following resources are created:


- resource.terraform_data.bootstrap (modules/supabase/vault-secrets/main.tf#L78)
- resource.terraform_data.npm_install (modules/supabase/vault-secrets/main.tf#L67)
- resource.terraform_data.reconcile (modules/supabase/vault-secrets/main.tf#L97)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_postgres_url"></a> [postgres\_url](#input\_postgres\_url) | Session-mode pooler URL (port 5432) for the target Supabase project.<br/>Transaction-mode pooler (port 6543) is NOT supported — CREATE EXTENSION<br/>and SECURITY DEFINER function invocation are unreliable through<br/>transaction-mode pooling.<br/>Format: postgresql://postgres.<project\_ref>:<password>@<host>:5432/postgres | `string` | n/a | yes |
| <a name="input_secrets"></a> [secrets](#input\_secrets) | Desired state of the Supabase Vault as a flat map of name → value.<br/>The reconcile provisioner upserts every entry and deletes any vault row<br/>whose name is NOT in this map (within the IaC-managed namespace).<br/><br/>Rules:<br/>- Names MUST be UPPER\_SNAKE\_CASE (^[A-Z][A-Z0-9\_]*$) — this is the<br/>  IaC namespace. Lowercase names are reserved for runtime-managed entries<br/>  (per-tenant OAuth tokens) and will be rejected by the reconcile script.<br/>- Empty string values are treated as "absent" and the entry is deleted.<br/>- Removing a key from this map deletes the corresponding vault entry on<br/>  the next apply.<br/><br/>Example:<br/>  secrets = {<br/>    XERO\_CLIENT\_ID     = "my-xero-client-id"<br/>    XERO\_CLIENT\_SECRET = "my-xero-client-secret"<br/>    OPENAI\_API\_KEY     = "sk-..."<br/>  } | `map(string)` | n/a | yes |
| <a name="input_supabase_ssl_cert"></a> [supabase\_ssl\_cert](#input\_supabase\_ssl\_cert) | Base64-encoded Supabase CA certificate chain for TLS verification of<br/>pooler connections. Required for Supabase pooler endpoints<br/>(*.pooler.supabase.com) — these use a self-signed certificate not<br/>present in standard CI runner CA stores.<br/>Default "" means no cert supplied; the scripts will fail fast for<br/>pooler endpoints unless PGSSL\_INSECURE\_NO\_VERIFY=1 is set (break-glass). | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_bootstrap_trigger_id"></a> [bootstrap\_trigger\_id](#output\_bootstrap\_trigger\_id) | Unique ID of the bootstrap terraform\_data resource; changes when the bootstrap script is re-run. |
| <a name="output_managed_secret_names"></a> [managed\_secret\_names](#output\_managed\_secret\_names) | Sorted list of secret names managed by this module. Visible in plan output — useful for verifying the desired-state map without exposing values. |
| <a name="output_reconcile_trigger_id"></a> [reconcile\_trigger\_id](#output\_reconcile\_trigger\_id) | Unique ID of the reconcile terraform\_data resource; changes when secrets are reconciled. |
<!-- END_TF_DOCS -->
