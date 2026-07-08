# Runbook: Add a New Environment

**When to use:** You need a new isolated GCP environment (e.g., `staging`, `production`) with its own spoke project, VPC, and service accounts.

**Time:** ~30 minutes  
**Risk:** Low — creates new resources, does not modify existing environments.  
**Prerequisites:** `envs/organization` has been applied at least once. You have Terraform Cloud access.

---

## Steps

### 1. Create a Terraform Cloud workspace

In the Terraform Cloud UI (or via the TFC API):

1. Go to your organization → **Workspaces** → **New workspace**
2. Name it `apps-{env}` (e.g., `apps-staging`)
3. Set execution mode: **Remote** (or **Agent** if using self-hosted runners)
4. Configure VCS connection to this repository, triggering on changes to `envs/apps/**`
5. Set the Terraform working directory to `envs/apps`

### 2. Add the environment to the organization root's `environments` map

Per-environment CIDR, region, and other config are **not** set in `envs/apps` tfvars — they live in the `environments` map in `envs/organization` and are read by `envs/apps` via `terraform_remote_state` (`environment_config[var.environment]`). See [cidr-expansion.md](cidr-expansion.md) for the authoritative model.

In your `envs/organization` tfvars (e.g. `local.auto.tfvars`), add a new entry:

```hcl
environments = {
  # ... existing environments unchanged ...
  staging = {
    display_name            = "Staging"
    region                  = "europe-west1"
    cidr_block              = "10.129.0.0/16"   # must not overlap dev (10.128.0.0/16), the hub, or any other spoke
    budget_monthly_limit    = 500
    iam_group_role_bindings = {}
  }
}
```

Choose a non-overlapping CIDR. Refer to [network-topology.md](../architecture/network-topology.md) for the subnet layout.

### 3. Apply the organization root

Applying the org root creates the new environment's folder and host project, registers the new `apps-staging` TFC workspace (workspace registration is consumed by `module.bootstrap`), and publishes the new `environment_config["staging"]` entry to remote state:

```bash
make plan-organization
# Confirm the plan creates the new folder, host project, and workspace registration —
# no changes to existing environments.
terraform -chdir=envs/organization apply
```

### 4. Create a tfvars file for the new environment

```bash
cp examples/dev.tfvars examples/staging.tfvars
```

Edit `examples/staging.tfvars` and set at minimum:

```hcl
environment    = "staging"
project_prefix = "ashes"
```

Do **not** set a CIDR here — `envs/apps` reads it from the organization remote state automatically.

Commit the file:

```bash
git add examples/staging.tfvars
git commit -m "feat: add staging environment tfvars"
```

### 5. Set workspace variables in Terraform Cloud

In the `apps-staging` workspace, set the following as a **Terraform variable**:

| Key | Value | Sensitive? |
|-----|-------|------------|
| `environment` | `staging` | No |

And as an **environment variable**:

| Key | Value |
|-----|-------|
| `TF_CLI_ARGS_plan` | `-var-file=examples/staging.tfvars` |

### 6. Trigger the first plan

Push to `main` or manually trigger the `apps-staging` workspace run in TFC. Review the plan carefully — it should create new resources only (no modifications to existing environments and no project creation, since the host project already exists from Step 3).

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
gcloud projects describe $(terraform -chdir=envs/apps output -raw host_project_id)

# Check VPC was created
gcloud compute networks describe $(terraform -chdir=envs/apps output -raw network_name) \
  --project=$(terraform -chdir=envs/apps output -raw host_project_id)
```

---

## Rollback

If the apply created partial resources and you need to clean up, the safest approach is:

```bash
terraform -chdir=envs/apps destroy -target=module.host -var-file=examples/staging.tfvars
```

Do not use `terraform destroy` without `-target` in a shared workspace — it will attempt to destroy all resources including those managed by other workspace runs.
