# SaaS Modules

Cross-provider SaaS orchestration. The Supabase and Vercel primitives live in
their own cloud groups ([`modules/supabase/`](../supabase/),
[`modules/vercel/`](../vercel/)); this group holds the stage that composes them.

| Stage | Composes | Invoked from |
|-------|----------|--------------|
| [stages/saas-workload](./stages/saas-workload/) | `supabase/environment`, `supabase/vault-secrets`, `vercel/project` | `envs/saas` (`TF_WORKSPACE=saas-<name>`) |

`saas-workload` is the only cross-provider module in the repo. It composes only
its own two providers (Supabase + Vercel), gated by `enable_supabase` /
`enable_vercel`, and reads **no** AWS/GCP state — the any-combination provider
model holds (an unused cloud's provider is physically absent). See
[Provider Selection](../../docs/architecture/provider-selection.md).
