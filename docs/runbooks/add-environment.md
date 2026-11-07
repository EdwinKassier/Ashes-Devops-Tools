# Runbook: Add a New Environment

**When to use:** You need a new isolated GCP environment (e.g., `staging`, `production`) with its own spoke project, VPC, and service accounts.

**Time:** one PR, then a few run confirmations
**Risk:** Low — creates new resources, does not modify existing environments.
**Prerequisites:**

- The handover is done: tfc-admin pass 2 has applied with `gcp_bootstrap_outputs_from_tfc = true`
  and `workspace_execution_modes = {}`, so `gcp-bootstrap` runs remotely in TFC.
- The four GCP control-plane roots have each applied at least once.
- `enable_run_triggers` is on (the default).

A **greenfield** estate still needs the phase-0 pass in [bootstrap.md](bootstrap.md) first. Until
`gcp-bootstrap` has outputs, tfc-admin cannot derive the new environment's service-account emails.

> **Five-root flow.** A new environment touches every GCP root, because each one derives
> something from the shared `environments` map (`gcp.environments` in the committed
> `config/landing-zone.yaml`, the single source every GCP root and tfc-admin reads): `gcp-bootstrap` grants WIF trust to the
> `gcp-workload-<env>` workspace, `gcp-organization` creates the environment folder,
> `gcp-projects` vends the host project and publishes `environment_config[<env>]`, and
> `gcp-network-hub` adds the new host project to the hub VPC-SC perimeter. `gcp-workload-<env>` then builds the
> spoke itself. All applies run in Terraform Cloud — never locally (see
> [CLAUDE.md → State & Apply Rules](../../CLAUDE.md#state--apply-rules)).

**How it runs.** tfc-admin is the root of the run-trigger DAG
(`tfc-admin → gcp-bootstrap → gcp-organization → gcp-projects → gcp-network-hub → gcp-workload-<env>`).
Each run is queued when its upstream **applies**; a no-op apply fires no trigger. Shared workspaces wait
for your confirmation. A workload whose environment sets `is_production: false` **explicitly** has
`auto_apply_run_trigger` and `queue_all_runs` (`enable_nonprod_workload_auto_apply`; by default only
while the policy sets and their `destroy_guard` are attached), so the run its upstream queues applies
on its own. Set `is_production: false` explicitly to opt an environment into
auto-apply: an omitted flag fails closed, so the workload waits for confirmation like production and
the shared workspaces.

> **Trust change.** Confirming a shared upstream apply (`gcp-network-hub`, `aws-network`,
> `aws-security`) also applies every non-production workload it triggers, with no second
> confirmation. Review the downstream effect before you confirm, or set
> `enable_nonprod_workload_auto_apply = false`. See [known gaps](../known-gaps.md#open--validate-before-relying-on).

---

## Steps

### 1. Edit `config/landing-zone.yaml` and merge

Per-environment CIDR, region, and other config are **not** set in `envs/gcp/workload` tfvars. They
live in the `environments` map and reach `envs/gcp/workload` through the `environment_config` that
`gcp-projects` publishes to remote state (`environment_config[var.environment]`). See
[cidr-expansion.md](cidr-expansion.md) for the authoritative model.

Add **one** entry under `gcp.environments` and open a PR. All four control-plane roots and tfc-admin
read the same map, so nothing needs to be kept in sync by hand:

```yaml
gcp:
  environments:
    # ... existing environments unchanged ...
    staging:
      display_name: Staging
      region: europe-west1          # optional, default org.regions.gcp
      cidr_block: 10.129.0.0/16     # must not overlap dev (10.128.0.0/16), the hub, or any other spoke
      budget_monthly_limit: 500
      is_production: false
      iam_group_role_bindings: {}
```

Choose a non-overlapping CIDR. Refer to [network-topology.md](../architecture/network-topology.md) and
the [CIDR plan](../architecture/cidr-plan.md) for the layout. Keep the key short:
`<org.prefix>-wl-<env>-apply` must fit the 30-character GCP service-account ID limit, and the tfc-admin
plan fails if it does not.

> **Explicit `environments` variable?** If a workspace sets `environments` explicitly (tfvars or a TFC
> variable), that value wins over the config file. Remove it so that the root reads the file, or add the
> entry there too.

Merge the PR. The config edit queues a run on tfc-admin and on every workspace that triggers on
`config/landing-zone.yaml`.

### 2. tfc-admin and the affected roots run

Confirm the **tfc-admin** apply (it never auto-applies). It:

- creates `gcp-workload-staging` with its `environment` variable, triggers and settings;
- sets its `TFC_GCP_*` env vars in the same apply. The SA emails are derived as
  `<org.prefix>-wl-staging-{plan,apply}@<admin_project_id>.iam.gserviceaccount.com`, with the admin
  project ID from the gcp-bootstrap outputs, so no second tfc-admin pass is needed. A `check` warns if
  a derived email differs from one gcp-bootstrap already outputs;
- triggers `gcp-bootstrap` (and `aws-organization`), the DAG roots.

### 3. Confirm each shared workspace as it queues

Each plan should show **additions only** for the new environment and no changes to existing ones.
Confirm them in order, as each queues (the triggers enforce the order):

| Order | Workspace | What the new environment adds |
|-------|-----------|-------------------------------|
| 1 | `gcp-bootstrap` | The `<prefix>-wl-staging-plan/-apply` SAs and WIF trust for the `gcp-workload-staging` workspace |
| 2 | `gcp-organization` | The environment folder (and its folder-level policies) |
| 3 | `gcp-projects` | The host project; publishes `environment_config["staging"]` |
| 4 | `gcp-network-hub` | Adds the new host project to the hub VPC-SC perimeter |

A plan with no changes ends as "planned and finished" and needs no action (tfc-admin triggers
`aws-organization` too, for example).
The config-edit runs from step 1 may already have queued some of these; confirm the latest.

### 4. The new non-prod workload creates itself and applies

When `gcp-network-hub` applies, its run trigger queues `gcp-workload-staging`. A workload with
`is_production: false` applies that run without confirmation. Any other workload (`is_production:
true`, or the flag omitted) waits for your confirmation; review its plan first.

`queue_all_runs` also queued a run when tfc-admin created the workspace. That run is **expected to
fail**: it started before `gcp-bootstrap` created the SAs. Ignore it. The setting exists so later VCS
and run-trigger runs queue without a manual first run. If
`gcp-network-hub`'s apply was a no-op (for example the VPC-SC perimeter is off), no trigger fires:
start one run on `gcp-workload-staging` by hand.

> **AWS workloads need a second tfc-admin pass.** A new `aws-workload-<env>` gets its `TFC_AWS_*` role
> ARNs from the `aws-organization` outputs, and a new workload account's roles exist only after
> `aws-organization` applies. Re-apply tfc-admin after that apply; follow
> [aws-add-account.md](aws-add-account.md).

### 5. (Optional) Workload tfvars, in the step-1 PR

A non-prod workload applies as soon as its upstream does, so put any tfvars file and its
`-var-file` wiring in the same PR as the config edit, not afterwards.

`environment` comes from tfc-admin, and `project_prefix` / `tfc_organization` / `region` come from
`config/landing-zone.yaml`. A tfvars file is needed only for workload-specific inputs (Cloud Armor,
app services, ...):

```bash
cp examples/dev.tfvars.example examples/staging.tfvars
```

Do **not** set a CIDR here — `envs/gcp/workload` reads it from the `gcp-projects` remote state (`environment_config`) automatically.

Commit the file:

```bash
git add examples/staging.tfvars
git commit -m "feat: add staging environment tfvars"
```

### 6. Point the workspace at the tfvars file (only if you created one)

tfc-admin already sets the `environment` Terraform variable. If you created a tfvars file in step 5, set
this **environment variable** through tfc-admin's `workspace_variables` input (`category = "env"`;
the committed `config/tfc-workspaces.yaml` rejects `TF_CLI_ARGS*`):

| Key | Value |
|-----|-------|
| `TF_CLI_ARGS_plan` | `-var-file=../../../examples/staging.tfvars` |

### 7. Verify

Review the first workload plan or apply log: it should create new resources only (no modifications
to existing environments and no project creation, since `gcp-projects` created the host project in
step 3).

```text
Expected new resources:
  + module.environment.module.host.module.network.module.vpc.google_compute_network.vpc
  + module.environment.module.host.module.network.module.private_subnets.*
  + module.environment.module.host.module.network.module.database_subnets.*
  + module.environment.module.host.module.integrated_nat.*
  (etc.)
```

Verify the environment is healthy:

```bash
# Check host project was created
gcloud projects describe $(terraform -chdir=envs/gcp/workload output -raw host_project_id)

# Check VPC was created
gcloud compute networks describe $(terraform -chdir=envs/gcp/workload output -raw network_name) \
  --project=$(terraform -chdir=envs/gcp/workload output -raw host_project_id)
```

---

## Rollback

If the apply created partial resources, follow [Apply Recovery](apply-recovery.md) (roll forward first).
To remove the environment entirely, queue a **destroy** run on the `gcp-workload-staging` workspace in
Terraform Cloud, then remove the entry from `gcp.environments` in `config/landing-zone.yaml` and apply the control-plane roots
in **reverse** order (`gcp-network-hub` → `gcp-projects` → `gcp-organization` → `gcp-bootstrap`). See
[Teardown](teardown.md) for the `prevent_destroy` and CMEK caveats.

Never run a targeted `terraform destroy` locally against a shared workspace.
