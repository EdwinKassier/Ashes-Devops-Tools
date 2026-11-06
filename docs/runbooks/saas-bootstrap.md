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

## Single-provider stacks

Set `supabase: false` or `vercel: false`. The unused provider then needs no token and creates
nothing. `envs/saas/tests/single_provider_*.tftest.hcl` covers both shapes.

## Teardown

Destroy the workspace from TFC. Supabase projects are paused and then deleted; export the
database first.
