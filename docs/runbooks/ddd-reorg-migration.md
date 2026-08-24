# Runbook — DDD reorg: repoint TFC workspace working directories

> **ONE-TIME MIGRATION (not a standing procedure).** Run once during the associated migration, then this runbook is historical — archive or ignore. See [`docs/known-gaps.md`](../known-gaps.md) for current status.

**When to use:** After the DDD-reorg `envs/` nesting PR merges. The env root
directories moved from a flat `envs/<cloud>-<layer>/` layout to a cloud-grouped
`envs/<cloud>/<layer>/` layout. Each Terraform Cloud workspace has a **VCS
working directory** setting that points at its root's path — that path changed,
so each workspace must be repointed once.

**This is a settings change, not a state migration.** Workspace **names**,
`backend.tf` `name`/`prefix` values, and all `terraform_remote_state` lookups
(which target workspaces by name) are unchanged. State is untouched. Release
tags map to workspaces, not paths, so the release workflow is unaffected.

## What changed

| Workspace | Old working directory | New working directory |
|---|---|---|
| `gcp-organization` | `envs/gcp-organization` | `envs/gcp/organization` |
| `gcp-workload-<env>` | `envs/gcp-workload` | `envs/gcp/workload` |
| `aws-organization` | `envs/aws-organization` | `envs/aws/organization` |
| `aws-security` | `envs/aws-security` | `envs/aws/security` |
| `aws-network` | `envs/aws-network` | `envs/aws/network` |
| `aws-identity` | `envs/aws-identity` | `envs/aws/identity` |
| `aws-shared-services` | `envs/aws-shared-services` | `envs/aws/shared-services` |
| `aws-backup` | `envs/aws-backup` | `envs/aws/backup` |
| `aws-workload-<env>` | `envs/aws-workload` | `envs/aws/workload` |
| `saas-<name>` | `envs/saas` | `envs/saas` (unchanged) |

`saas-*` did not move — no action for those workspaces.

## Procedure

Do this **before** the next apply of each workspace. A workspace still pointed
at the old path will fail fast on its next run (the directory no longer exists),
so there is no silent-drift risk — but repoint proactively to avoid a failed run.

### Option A — Terraform Cloud UI

For each workspace above (except `saas-*`):

1. Workspace → **Settings → General**.
2. Set **Terraform Working Directory** to the new path from the table.
3. If **VCS triggers** list path prefixes, update `envs/<cloud>-<layer>/**` →
   `envs/<cloud>/<layer>/**`.
4. **Save settings.** Do not queue a plan yet — let the next normal PR/tag flow
   trigger it, or queue one manually once all workspaces are repointed.

### Option B — TFC API (scriptable)

Set `TFC_TOKEN` (owners/admin) and `ORG`, then for each `WS`/`DIR` pair:

```bash
curl -s --header "Authorization: Bearer $TFC_TOKEN" \
     --header "Content-Type: application/vnd.api+json" \
     --request PATCH \
     "https://app.terraform.io/api/v2/organizations/$ORG/workspaces/$WS" \
     --data "{\"data\":{\"type\":\"workspaces\",\"attributes\":{\"working-directory\":\"$DIR\"}}}" \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["data"]["attributes"]["name"], "->", d["data"]["attributes"]["working-directory"])'
```

Pairs (`WS` → `DIR`):

```text
gcp-organization      envs/gcp/organization
gcp-workload-<env>    envs/gcp/workload         # one per gcp-workload-* workspace
aws-organization      envs/aws/organization
aws-security          envs/aws/security
aws-network           envs/aws/network
aws-identity          envs/aws/identity
aws-shared-services   envs/aws/shared-services
aws-backup            envs/aws/backup
aws-workload-<env>    envs/aws/workload         # one per aws-workload-* workspace
```

## Verification

1. In each repointed workspace, **Actions → Start new run → Plan only**.
2. Confirm the plan initializes from the new working directory and shows **no
   resource changes** (a pure path move must not alter any resource).
3. If a plan shows unexpected diffs, stop and investigate before applying — do
   not apply a plan you did not expect.

## Rollback

If needed, set the working directory back to the old `envs/<cloud>-<layer>`
path — but only if the reorg PR is also reverted, since the old directories no
longer exist on the default branch after merge.
