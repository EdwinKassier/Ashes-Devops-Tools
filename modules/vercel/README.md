# Vercel Modules

Terraform modules for provisioning and managing Vercel projects. These modules are consumed by [`modules/stages/saas-workload`](../stages/saas-workload/) and can also be called directly.

## Modules

| Module | Purpose |
|:-------|:--------|
| [`project`](project/) | Creates a Vercel project with three environments (QA/preview, UAT/custom, production). Handles sensitive environment variable drift via `terraform_data` SHA256 triggers. POSIX-sh `ignore_command` for branch filtering. |

## Provider

All modules require the `vercel/vercel ~> 4.0` provider configured via:

```bash
export VERCEL_API_TOKEN="your_vercel_token_here"
```

Generate a token at [vercel.com/account/tokens](https://vercel.com/account/tokens). Prefer a **team token** for org-wide deployments.

> **Note:** If calling `modules/stages/saas-workload`, the Vercel provider must be configured even when `enable_vercel = false`. For Supabase-only deployments without the Vercel provider dependency, call `modules/supabase/environment` directly.

## See Also

- [Quick Start → Section 3a](../../docs/guides/QUICK_START.md#3a-configure-supabase-and-vercel-provider-credentials) — token setup
- [Architecture → SaaS Modules](../../docs/architecture/ARCHITECTURE.md#saas-modules) — design decisions
