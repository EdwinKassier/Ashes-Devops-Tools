# Runbook — Rename GCP TFC Workspaces (`organization` → `gcp-organization`, `apps-<env>` → `gcp-workload-<env>`)

**When to use:** Once, after pulling the change that renamed the GCP roots
(`envs/organization` → `envs/gcp-organization`, `envs/apps` → `envs/gcp-workload`).
The code now expects Terraform Cloud workspaces named `gcp-organization` and
`gcp-workload-<env>`. Until you rename the live workspaces to match, applies will
target the old names via the old backend config and drift from the repo.

**Who:** A TFC user with **admin** on the affected workspaces.

**Blast radius:** Workspace **names** only. No Terraform resources are created,
destroyed, or moved. Renaming a workspace in TFC keeps its state, variables, run
history, and VCS connection intact.

> **This is the only step that touches live infrastructure.** Everything else in the
> rename (directories, backends, workflows, docs, Makefile) is already in the repo.

---

## Why no `state mv` / `moved` blocks

Renaming a workspace is a control-plane rename in Terraform Cloud — the state object
and every resource address inside it are unchanged. `moved` blocks and `terraform
state mv` are for **resource address** changes; this change has none. Do **not** add
any.

---

## Pre-flight

1. Merge the rename PR to `main` (so the backend `name`/`prefix` values in the repo
   already say `gcp-organization` / `gcp-workload-`).
2. Confirm no runs are in progress on the affected workspaces.
3. List the workspaces you must rename:

   ```text
   organization        → gcp-organization
   apps-dev            → gcp-workload-dev
   apps-uat            → gcp-workload-uat
   apps-prod           → gcp-workload-prod
   apps-<env>          → gcp-workload-<env>     # for every environment you run
   ```

---

## Option A — Rename in the TFC UI (recommended)

For each workspace:

1. **Workspace → Settings → General**.
2. Change **Name** to the new value (e.g. `organization` → `gcp-organization`).
3. **Save settings**.

TFC preserves state and variables. Repeat for every `apps-<env>` → `gcp-workload-<env>`.

## Option B — Rename via the TFC API

```bash
# Requires: TFC_TOKEN (owner/admin), TFC_ORG set to your org name.
rename_ws() {
  local old="$1" new="$2"
  curl -s --header "Authorization: Bearer ${TFC_TOKEN}" \
       --header "Content-Type: application/vnd.api+json" \
       --request PATCH \
       "https://app.terraform.io/api/v2/organizations/${TFC_ORG}/workspaces/${old}" \
       --data "{\"data\":{\"type\":\"workspaces\",\"attributes\":{\"name\":\"${new}\"}}}" \
    | grep -q "\"name\":\"${new}\"" && echo "renamed ${old} -> ${new}" || echo "FAILED ${old}"
}

rename_ws organization gcp-organization
rename_ws apps-dev  gcp-workload-dev
rename_ws apps-uat  gcp-workload-uat
rename_ws apps-prod gcp-workload-prod
# ...one line per environment you actually run
```

---

## Re-point local state and verify

The backend config in the repo already carries the new names
(`envs/gcp-organization/backend.tf` → `name = "gcp-organization"`;
`envs/gcp-workload/backend.tf` → `prefix = "gcp-workload-"`). Re-init locally so your
CLI state points at the renamed workspaces:

```bash
# Control plane
terraform -chdir=envs/gcp-organization init -reconfigure
make plan-gcp-organization        # expect: no changes

# Each workload environment
TF_WORKSPACE=gcp-workload-dev terraform -chdir=envs/gcp-workload init -reconfigure
make plan-gcp-workload APP_ENV=dev APP_VARS=examples/dev.tfvars   # expect: no changes
```

A **clean plan (no changes)** on every renamed workspace confirms the migration:
same state, new name.

---

## Downstream references to update (outside this repo)

These live *outside* Terraform and are **not** changed by the code rename — update them
by hand:

- **Drift detection variable** — set the `TFC_DRIFT_WORKSPACES` repository variable to
  the new names, e.g. `["gcp-organization","gcp-workload-dev","gcp-workload-prod", ...]`.
  (The workflow's inline default is already `["gcp-organization","gcp-workload-dev"]`.)
- **Release tags** — cut future releases as `gcp-organization/vX.Y.Z` and
  `gcp-workload/<env>/vX.Y.Z`. Old-format tags no longer match `terraform-apply.yml`
  and will fail with an "Unrecognized release tag" error.
- **`TFC_TOKEN` team-token scope** — if it was scoped to the `organization` workspace by
  name, re-scope it to `gcp-organization`.
- **Any external dashboards, notification integrations, or bookmarks** that referenced
  the old workspace names.

---

## Rollback

If you must revert before renaming workspaces: revert the rename commit. The repo goes
back to `envs/organization` / `envs/apps` with backend names `organization` /
`apps-`, matching the still-original workspaces. If you already renamed the workspaces
in TFC, rename them back (`gcp-organization` → `organization`, etc.) using the same
steps above.
