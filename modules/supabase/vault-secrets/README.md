# Supabase Vault Secrets Module

Bootstraps the Supabase Vault with helper functions and reconciles a desired-state map of secrets.

## Runtime Requirements

- **Node.js >= 18** must be in the execution environment's `PATH`.
- **`SUPABASE_ACCESS_TOKEN`** (env var) — required in CI to use the Management API path, which bypasses the Supavisor pooler and avoids the common _"Tenant or user not found"_ error on GitHub Actions runners.
- **`SUPABASE_SSL_CERT`** (base64-encoded CA bundle) — required for `*.pooler.supabase.com` connections. Fetch from the Supabase dashboard → Project Settings → Database → SSL Certificate.

## Install script dependencies

```bash
cd modules/supabase/vault-secrets/scripts && npm install
```

## IaC Namespace

Only secrets whose names match `^[A-Z][A-Z0-9_]*$` (UPPER_SNAKE_CASE) are managed. Lowercase and mixed-case names (runtime-managed per-tenant entries) are never touched.

## Safety Guard

If `var.secrets` is empty and the vault already contains entries, the reconcile script **refuses to apply** to prevent accidental data loss. Set `VAULT_ALLOW_EMPTY_DESIRED=1` in the environment to override.

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
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_null"></a> [null](#requirement\_null) | ~> 3.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_null"></a> [null](#provider\_null) | 3.2.4 |



## Resources

The following resources are created:


- resource.null_resource.bootstrap (modules/supabase/vault-secrets/main.tf#L25)
- resource.null_resource.reconcile (modules/supabase/vault-secrets/main.tf#L45)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_postgres_url"></a> [postgres\_url](#input\_postgres\_url) | Session-mode pooler URL (port 5432) for the target Supabase project.<br/>Transaction-mode pooler (port 6543) is NOT supported — CREATE EXTENSION<br/>and SECURITY DEFINER function invocation are unreliable through<br/>transaction-mode pooling.<br/>Format: postgresql://postgres.<project\_ref>:<password>@<host>:5432/postgres | `string` | n/a | yes |
| <a name="input_secrets"></a> [secrets](#input\_secrets) | Desired state of the Supabase Vault as a flat map of name → value.<br/>The reconcile provisioner upserts every entry and deletes any vault row<br/>whose name is NOT in this map (within the IaC-managed namespace).<br/><br/>Rules:<br/>- Names MUST be UPPER\_SNAKE\_CASE (^[A-Z][A-Z0-9\_]*$) — this is the<br/>  IaC namespace. Lowercase names are reserved for runtime-managed entries<br/>  (per-tenant OAuth tokens) and will be rejected by the reconcile script.<br/>- Empty string values are treated as "absent" and the entry is deleted.<br/>- Removing a key from this map deletes the corresponding vault entry on<br/>  the next apply.<br/><br/>Example:<br/>  secrets = {<br/>    XERO\_CLIENT\_ID     = "my-xero-client-id"<br/>    XERO\_CLIENT\_SECRET = "my-xero-client-secret"<br/>    OPENAI\_API\_KEY     = "sk-..."<br/>  } | `map(string)` | n/a | yes |
| <a name="input_supabase_ssl_cert"></a> [supabase\_ssl\_cert](#input\_supabase\_ssl\_cert) | Base64-encoded Supabase CA certificate chain for TLS verification of<br/>pooler connections. Required for Supabase pooler endpoints<br/>(*.pooler.supabase.com) — these use a self-signed certificate not<br/>present in standard CI runner CA stores.<br/>Default "" means no cert supplied; the scripts will fail fast for<br/>pooler endpoints unless PGSSL\_INSECURE\_NO\_VERIFY=1 is set (break-glass). | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_managed_secret_names"></a> [managed\_secret\_names](#output\_managed\_secret\_names) | Sorted list of secret names managed by this module. Visible in plan output — useful for verifying the desired-state map without exposing values. |
<!-- END_TF_DOCS -->
