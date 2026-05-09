# Supabase Modules

Terraform modules for provisioning and managing Supabase resources. These modules are consumed by [`modules/stages/saas-workload`](../stages/saas-workload/) and can also be called directly for Supabase-only deployments.

## Modules

| Module | Purpose |
|:-------|:--------|
| [`project`](project/) | Creates a Supabase project via `supabase_project`. Lifecycle guard ignores `database_password` after initial creation — the Management API does not re-expose the password. |
| [`settings`](settings/) | Manages auth and API settings on an existing project via `supabase_settings`. Destroying this resource is a no-op by provider design — settings revert to Supabase defaults. |
| [`environment`](environment/) | Composite module: `project` + `settings` + `data.supabase_apikeys`. Primary building block for per-environment deployments. The `anon_key` output is intentionally non-sensitive. |
| [`vault-secrets`](vault-secrets/) | Bootstraps the Supabase Vault with `SECURITY DEFINER` helper functions and reconciles a desired-state `map(string)` of secrets. Requires **Node.js >= 18** and `pg ^8.20.0`. |

## Provider

All modules require the `supabase/supabase ~> 1.0` provider configured via:

```bash
export SUPABASE_ACCESS_TOKEN="sbp_your_token_here"
```

Generate a token at [app.supabase.com/account/tokens](https://app.supabase.com/account/tokens) with **Manage organization** scope.

## Node.js Requirement

`vault-secrets` executes Node.js scripts at apply time. Install dependencies once after cloning:

```bash
cd modules/supabase/vault-secrets/scripts
npm install
```

## See Also

- [Quick Start → Section 3a](../../docs/guides/QUICK_START.md#3a-configure-supabase-and-vercel-provider-credentials) — token setup
- [Troubleshooting → Supabase errors](../../docs/guides/TROUBLESHOOTING.md#supabase-module-errors) — common errors
