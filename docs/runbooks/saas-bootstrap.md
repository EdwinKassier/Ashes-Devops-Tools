# Runbook — Stand Up the SaaS Layer (Supabase and/or Vercel)

The SaaS path is the fastest route to a running app: one root (`envs/saas`), one workspace per
stack (`saas-<name>`), and no cloud account at all. Either provider can be used alone.

**Time:** about an hour once the tokens exist.

## Prerequisites

- A Terraform Cloud organization, with the `tfc-admin` workspace created
  ([bootstrap runbook](bootstrap.md#creating-and-wiring-the-tfc-workspaces-tfc-admin-two-pass)).
- **Supabase:** an organization, and its ID from the dashboard URL
  `supabase.com/dashboard/org/<id>`. Also a personal access token with **Manage organization**
  scope.
- **Vercel:** a team ID (Settings → General), a token scoped to that team, and the Vercel
  GitHub App installed on the repository Vercel deploys.

## 1. Configure the stacks in `config/landing-zone.yaml`

```yaml
saas:
  enabled: true
  workspaces: [web]          # one saas-<name> workspace per entry
  supabase: true             # enable_supabase
  vercel: true               # enable_vercel
  defaults:
    supabase: {organization_id: abcdefgh12345678, region: eu-west-2}
    vercel: {team_id: team_abc123}
  stacks:
    web:
      supabase: {project_name: acme-web}
      vercel: {project_name: acme-web, github_repo: acme/web, production_branch: main}
```

The file holds IDs and names only. Commit it.

## 2. Create the workspaces and inject the secrets (tfc-admin)

Apply `tfc-admin`. It creates `saas-web` and sets its `stack` variable. It also turns off
speculative PR plans on it, because the SaaS tokens are account-wide (`disable_speculative_on_saas`).
Pass the three secrets through `workspace_variables`. They are written **write-only**, so they never
enter tfc-admin's state. Increment `version` to rotate one.

```hcl
workspace_variables = {
  "saas-web" = {
    SUPABASE_ACCESS_TOKEN      = { value = "sbp_...", category = "env", sensitive = true }
    VERCEL_API_TOKEN           = { value = "...", category = "env", sensitive = true }
    supabase_database_password = { value = "<32+ random chars>", sensitive = true }
  }
}
```

Use a **separate Supabase organization and Vercel team for production**, each with its own token.
A token from one organization cannot then touch another environment's projects.

## 3. Plan and apply `saas-web`

Queue a run on `saas-web`, or merge to `main`. The first apply creates the Supabase project, its
settings and environment wiring, and the Vercel project linked to the repository. The environment
variables come from `vercel_*_env_vars`.

## 4. Verify

- The Supabase dashboard shows the project in the configured region.
- In Vercel, a push to a branch creates a preview deployment and a push to `production_branch`
  deploys production.
- `terraform output` on `saas-web` lists the project URLs. The anon key is public by design. The
  service-role key and database password are sensitive outputs: rotate the password after the first
  apply (see [known gaps](../known-gaps.md)).

## Bridging secrets to a workload, and rotating them

A workload root with `enable_saas_secret_bridge = true` copies `supabase_api_url`,
`supabase_service_role_key` and `supabase_database_password` from `saas-<name>` into a Secrets
Manager (AWS) or Secret Manager (GCP) secret. It reads them with `ephemeral "tfe_outputs"` and
writes them with a write-only argument, so they are in neither the workload's plan nor its state.

**Reader team (an organization owner, once).** Create a team named `saas-outputs-reader` with no
organization access flags. Put its ID into tfc-admin's `saas_outputs_reader_team_id`. tfc-admin then
grants it custom access on every `saas-*` workspace and nothing else: `state_versions =
read-outputs`, runs read-only, no variables. Create a team token with a unique description and an
`expired_at` 90 days out. Store it as the sensitive environment variable `TFE_TOKEN` only on the
workload workspaces that set `enable_saas_secret_bridge`, through tfc-admin's write-only
`workspace_variables`. tfc-admin never creates the token, so the token is in no state. Rotate it
like the [tfc-admin token](tfc-admin-token-rotation.md#3-rotate-every-90-days-or-on-any-suspected-exposure).
The bridge reads saas outputs with this token, through the reader team's grant, not through
remote-state sharing (`extra_remote_state_consumers`). A workload with the bridge off needs no
`TFE_TOKEN`: its `tfe` provider gets an inert placeholder.

**Rotation counter.** `saas.bridge_rotation` in `config/landing-zone.yaml` (default `1`) is
published by `saas-<name>` as the non-sensitive `bridge_version` output, and read directly from the
same file by each bridging workload as its write-only version (`saas_bridge_version` overrides it
per workload). A write-only secret argument cannot be diffed, so a bridging workload re-pushes the
secret only when that number changes. Until `saas-<name>` has applied and published the new
number, the workload's plan fails on purpose (it would otherwise push the old values under the new
version). Apply `saas-<name>` first, then re-queue each bridging workload by hand: no run trigger
connects them. For an emergency workload change in that window, set `saas_bridge_version` on the
workload to the old value temporarily, and remove it once `saas-<name>` has applied.

**Rotating the service-role key.** Supabase reissues the anon and service-role keys when you
generate a new JWT secret (dashboard: Project Settings -> API).

1. Generate the new JWT secret in the dashboard.
2. Bump `saas.bridge_rotation` in the same pull request that records the rotation, and merge it.
3. Apply `saas-<name>`. It reads the new keys, updates the Vercel environment variables and
   publishes the new `bridge_version`.
4. Start a run on each bridging workload (no run trigger does it). It writes a new secret version. Restart or redeploy the
   consumers that cache the old value.

**Rotating the database password.** The Supabase provider cannot rotate it: the module sets it once
at creation and ignores later changes, so the `supabase_database_password` output keeps the
creation-time value, which stays in `saas-<name>` state (see [known gaps](../known-gaps.md)).

1. Reset the password in the dashboard (Project Settings -> Database).
2. Write the new value into each bridged secret directly, as a new version of the AWS or GCP
   secret.
3. Do **not** bump `saas.bridge_rotation` for this rotation alone. A bump re-pushes the stale
   creation-time password over the value you wrote. If a later service-role-key rotation needs a
   bump, write the database password into the secret again afterwards.

## Single-provider stacks

Set `supabase: false` or `vercel: false`. The unused provider then needs no token and creates
nothing. `envs/saas/tests/single_provider_*.tftest.hcl` covers both shapes.

## Teardown

Destroy the workspace from TFC. Supabase projects are paused and then deleted; export the
database first.
