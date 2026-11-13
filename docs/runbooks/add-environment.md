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

> **Multi-root flow.** A new environment touches every GCP root, because each one derives
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
on its own. Set `is_production: false` to opt an environment into auto-apply, or
`is_production: true` to keep the workload waiting for confirmation like the shared workspaces. The
flag is required: the plan fails when an environment omits it.

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
      region: europe-west1          # optional, default org.regions.gcp; the hub egress proxy needs the hub region
      cidr_block: 10.13.0.0/16      # next free /16 in the GCP block (docs/architecture/cidr-plan.md); tfc-admin fails on any overlap
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

**Production environments (`is_production: true`).** The plans fail until you make these choices, so
put them in the same PR:

- **Zones.** Set `gcp.environments.<env>.zones` to zones of the environment's region, in subnet
  order (check the names with `gcloud compute zones list --filter=region:<region>`). Without them
  the `gcp-workload-<env>` plan fails. For the first production environment, also set
  `gcp.network.zones` for the hub region: the `gcp-network-hub` plan fails without it as soon as
  any environment is production.
- **Egress.** Set `gcp.environments.<env>.egress_proxy: true` (it needs `secure_web_proxy` on
  `gcp-network-hub`, which is PREVIEW), or set `production_egress_proxy_waiver = { reason, expires }`
  on the `gcp-workload-<env>` workspace in `config/tfc-workspaces.yaml`. A standalone environment
  (no hub) needs the waiver. The hub proxy serves only environments in the hub region
  (`org.regions.gcp`): Google requires a Private Service Connect endpoint "in the same region as the
  published service", and the plan fails otherwise. An environment in another region (for example
  `europe-west1` with the hub in `europe-west2`) cannot use the hub proxy; as production it needs the
  waiver ([known-gaps](../known-gaps.md)). With the proxy on, every Cloud Run service and job defaults
  to `ALL_TRAFFIC` egress and gets `HTTPS_PROXY`, `HTTP_PROXY` and `NO_PROXY`; production rejects an
  explicit `vpc_egress: PRIVATE_RANGES_ONLY`.
- **VPC-SC.** The perimeter starts in dry-run, and a production plan fails on a dry-run perimeter.
  Enforce it (`vpc_sc_enable_dry_run = false`) or set `production_vpc_sc_dry_run_waiver` on the same
  workspace for a first rollout.

[production-hardening.md](production-hardening.md#1-vpc-service-controls-promote-from-dry-run-to-enforced-audit-m2)
explains each choice and the waiver format. A waiver stops working after its `expires` date, and the
plan fails again.

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
| 5 | `gcp-network-hub` (second run, step 5) | The hub-side peering `hub-to-<env>` |

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

### 5. Run gcp-network-hub again to peer the hub side

The hub side of the peering (`hub-to-<env>`) can only be created once `gcp-workload-<env>` has
created the spoke network: GCP rejects a peering to a network that does not exist. So the first
workload apply leaves its spoke side `INACTIVE`, and the workload plan warns with the
`hub_peering_active` check. Queue a run of `gcp-network-hub` and apply it. Then re-plan
`gcp-workload-<env>`: its `hub_peering_state` output reads `ACTIVE` and the `hub_peering_active`
check passes. Skip this step for `connectivity: ncc`.

This run stays manual: a run trigger from `gcp-workload-<env>` back to `gcp-network-hub` would
close a cycle in the run-trigger graph that tfc-admin builds.

The hub VPC holds at most `hub_peering_limit` environment peerings (default 24: the default
`PEERINGS_PER_NETWORK` quota is 25, and the hub's Private Service Access connection is one
peering). Above it the `gcp-network-hub` plan fails. Raise the quota and the limit, or move
environments to NCC ([gcp-peering-to-ncc-migration.md](gcp-peering-to-ncc-migration.md)).

### 6. (Optional) Workload tfvars, in the step-1 PR

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

### 7. Point the workspace at the tfvars file (only if you created one)

tfc-admin already sets the `environment` Terraform variable. If you created a tfvars file in step 6, set
this **environment variable** through tfc-admin's `workspace_variables` input (`category = "env"`;
the committed `config/tfc-workspaces.yaml` rejects `TF_CLI_ARGS*`). The `tfc_admin_guard` policy stops that
tfc-admin run until the security team overrides it, because `TF_CLI_ARGS*` changes how the CLI runs:

| Key | Value |
|-----|-------|
| `TF_CLI_ARGS_plan` | `-var-file=../../../examples/staging.tfvars` |

### 8. Verify

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
