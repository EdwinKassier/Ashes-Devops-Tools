# Runbook: Add a New Environment

**When to use:** You need a new isolated GCP environment (e.g., `staging`, `production`) with its own spoke project, VPC, and service accounts.

**Time:** ~30 minutes
**Risk:** Low — creates new resources, does not modify existing environments.
**Prerequisites:** the four GCP control-plane roots — `gcp-bootstrap`, `gcp-organization`, `gcp-projects` and `gcp-network-hub` — have each been applied at least once. You have Terraform Cloud access.

> **Five-root flow.** A new environment touches every GCP root, because each one derives
> something from the shared `environments` map (`gcp.environments` in the committed
> `config/landing-zone.yaml`, the single source every GCP root and tfc-admin reads): `gcp-bootstrap` grants WIF trust to the
> `gcp-workload-<env>` workspace, `gcp-organization` creates the environment folder,
> `gcp-projects` vends the host project and publishes `environment_config[<env>]`, and
> `gcp-network-hub` adds the new host project to the hub VPC-SC perimeter. `gcp-workload-<env>` then builds the
> spoke itself. All applies run in Terraform Cloud — never locally (see
> [CLAUDE.md → State & Apply Rules](../../CLAUDE.md#state--apply-rules)).

---

## Steps

### 1. Add the environment to `config/landing-zone.yaml`

Per-environment CIDR, region, and other config are **not** set in `envs/gcp/workload` tfvars. They
live in the `environments` map and reach `envs/gcp/workload` through the `environment_config` that
`gcp-projects` publishes to remote state (`environment_config[var.environment]`). See
[cidr-expansion.md](cidr-expansion.md) for the authoritative model.

Add **one** entry under `gcp.environments` and commit it. All four control-plane roots and tfc-admin
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
the [CIDR plan](../architecture/cidr-plan.md) for the layout.

> **Explicit `environments` variable?** If a workspace sets `environments` explicitly (tfvars or a TFC
> variable), that value wins over the config file. Remove it so that the root reads the file, or add the
> entry there too.

### 2. Create the Terraform Cloud workspace (tfc-admin)

Re-apply the `tfc-admin` workspace (`envs/tfc-admin`). It derives one `gcp-workload-<env>` workspace per
`gcp.environments` key, with the right working directory, VCS trigger, variable sets and the
`environment` variable set from the workspace name.

Manual fallback, in the Terraform Cloud UI (or via the TFC API):

1. Go to your organization → **Workspaces** → **New workspace**
2. Name it `gcp-workload-{env}` (e.g., `gcp-workload-staging`)
3. Set execution mode: **Remote** (or **Agent** if using self-hosted runners)
4. Configure VCS connection to this repository, triggering on changes to `envs/gcp/workload/**`
5. Set the Terraform working directory to `envs/gcp/workload`

### 3. Apply the control-plane roots, in order, in Terraform Cloud

Queue a run on each workspace and wait for it to finish before starting the next — each reads the
previous one's remote state. Preview locally first if you like (e.g.
`terraform -chdir=envs/gcp/projects plan`); every plan should show **additions only** for the new
environment and no changes to existing ones.

| Order | Workspace | What the new environment adds |
|-------|-----------|-------------------------------|
| 1 | `gcp-bootstrap` | WIF trust for the `gcp-workload-staging` workspace |
| 2 | `gcp-organization` | The environment folder (and its folder-level policies) |
| 3 | `gcp-projects` | The host project; publishes `environment_config["staging"]` |
| 4 | `gcp-network-hub` | Adds the new host project to the hub VPC-SC perimeter |

### 4. (Optional) Create a tfvars file for the new environment

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

### 5. Point the workspace at the tfvars file (only if you created one)

tfc-admin already sets the `environment` Terraform variable. If you created a tfvars file in step 4, set
this **environment variable**, either on the workspace or in `config/tfc-workspaces.yaml` with
`category: env`:

| Key | Value |
|-----|-------|
| `TF_CLI_ARGS_plan` | `-var-file=../../../examples/staging.tfvars` |

### 6. Trigger the first plan

Push to `main` or manually trigger the `gcp-workload-staging` workspace run in TFC. Review the plan carefully — it should create new resources only (no modifications to existing environments and no project creation, since `gcp-projects` already created the host project in Step 3).

```text
Expected new resources:
  + module.host.module.vpc.google_compute_network.vpc
  + module.host.module.private_subnets.*
  + module.host.module.database_subnets.*
  + module.host.module.nat.*
  (etc.)
```

### 7. Apply and verify

After plan review, approve the apply in TFC.

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
