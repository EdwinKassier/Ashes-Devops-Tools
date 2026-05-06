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

### 2. Create a tfvars file for the new environment

```bash
cp examples/dev.tfvars examples/staging.tfvars
```

Edit `examples/staging.tfvars` and set at minimum:

```hcl
environment    = "staging"
project_prefix = "ashes"
vpc_cidr_block = "10.129.0.0/16"   # must not overlap dev (10.128.0.0/16) or any other VPC
```

Choose a non-overlapping CIDR. Refer to [network-topology.md](../architecture/network-topology.md) for the subnet layout.

Commit the file:

```bash
git add examples/staging.tfvars
git commit -m "feat: add staging environment tfvars"
```

### 3. Add the new workspace to the TFC organization variables (if applicable)

If your `envs/organization` root manages TFC workspace configuration, add the new workspace name to the relevant variable and apply:

```bash
terraform -chdir=envs/organization apply -target=module.projects
```

### 4. Set workspace variables in Terraform Cloud

In the `apps-staging` workspace, set the following as **Terraform variables**:

| Key | Value | Sensitive? |
|-----|-------|------------|
| `environment` | `staging` | No |
| `vpc_cidr_block` | `10.129.0.0/16` | No |

And as an **environment variable**:

| Key | Value |
|-----|-------|
| `TF_CLI_ARGS_plan` | `-var-file=examples/staging.tfvars` |

### 5. Trigger the first plan

Push to `main` or manually trigger the workspace run in TFC. Review the plan carefully — it should create new resources only (no modifications to existing environments).

```
Expected new resources:
  + google_project.spoke_project
  + module.host.module.vpc.google_compute_network.vpc
  + module.host.module.private_subnets.*
  + module.host.module.database_subnets.*
  + module.host.module.nat.*
  (etc.)
```

### 6. Apply and verify

After plan review, approve the apply in TFC.

Verify the environment is healthy:

```bash
# Check host project was created
gcloud projects describe $(terraform -chdir=envs/apps output -raw host_project_id)

# Check VPC was created
gcloud compute networks describe $(terraform -chdir=envs/apps output -raw network_name) \
  --project=$(terraform -chdir=envs/apps output -raw host_project_id)
```

### 7. Update Dependabot (if needed)

If you committed a new root directory under `envs/`, add it to `.github/dependabot.yml`:

```yaml
- directory: "/envs/staging"
  schedule:
    interval: weekly
```

---

## Rollback

If the apply created partial resources and you need to clean up, the safest approach is:

```bash
terraform -chdir=envs/apps destroy -target=module.host -var-file=examples/staging.tfvars
```

Do not use `terraform destroy` without `-target` in a shared workspace — it will attempt to destroy all resources including those managed by other workspace runs.
