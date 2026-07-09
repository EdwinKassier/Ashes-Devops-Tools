# Runbook: Service Team Onboarding

**When to use:** A new application team needs their own GCP service project attached to the Shared VPC, with Workload Identity bindings for their workloads.

**Time:** 20–30 minutes.  
**Risk:** Low — adds new resources, does not modify existing spoke projects.  
**Prerequisites:** `envs/organization` and at least one `envs/apps` environment have been applied. The team's admin group email and billing account are known.

---

## Overview

Each service team gets:

1. A GCP project (created in `modules/stages/workload`)
2. Shared VPC attachment (the team's VMs use the existing host network)
3. IAM bindings for their admin Google Group

> **WIF note:** The bootstrap module's WIF pool is hardcoded to a single GitHub repository (`var.github_org`/`var.github_repo`). To grant a new team's GitHub repository access to GCP, you must either: (a) update `github_org`/`github_repo` if it is a monorepo, or (b) manually create a WIF pool binding for their repo using `gcloud iam workload-identity-pools providers` outside of Terraform.

---

## Steps

### Step 1 — Gather team information

Before starting, collect:

| Item | Example |
|------|---------|
| Project name (used in GCP project ID) | `payments` |
| Admin Google Group email | `payments-admins@company.com` |
| Folder ID to create the project in | `folders/987654321` |
| Billing account ID | `012345-6789AB-CDEF01` |
| Required IAM roles on their project | `["roles/bigquery.dataEditor"]` |
| Subnets from host project (region + name pairs) | See host project outputs |
| APIs to enable | `["bigquery.googleapis.com", "run.googleapis.com"]` |

### Step 2 — Get the host project outputs

```bash
# Get the host project ID and subnet names
terraform -chdir=envs/apps output host_project_id
terraform -chdir=envs/apps output subnets
```

The `subnets` output is a map. Each key is a subnet identifier; each value contains `region` and `self_link`.

### Step 3 — Add a workload module call in `envs/apps/main.tf`

```hcl
module "workload_payments" {
  source = "../../modules/stages/workload"

  project_name    = "payments"
  org_id          = data.terraform_remote_state.organization.outputs.org_id
  folder_id       = data.terraform_remote_state.organization.outputs.environment_config[var.environment].folder_id
  billing_account = data.terraform_remote_state.organization.outputs.billing_account

  activate_apis = [
    "bigquery.googleapis.com",
    "run.googleapis.com",
    "storage.googleapis.com",
  ]

  labels = {
    team        = "payments"
    environment = var.environment
  }

  # Attach to Shared VPC
  enable_shared_vpc_attachment = true
  shared_vpc_host_project_id   = module.host.host_project_id

  # Subnet access — provide the region and subnet name for each subnet to grant
  shared_vpc_subnets = {
    "private" = {
      region      = var.region
      subnet_name = "${var.project_prefix}-private"
    }
    "database" = {
      region      = var.region
      subnet_name = "${var.project_prefix}-database"
    }
  }

  # Google Group that acts as project admin
  project_admin_group_email = "payments-admins@company.com"

  # Roles granted to the admin group (additive per-role — do NOT include owner/editor/viewer)
  project_admin_roles = [
    "roles/bigquery.dataEditor",
    "roles/storage.objectAdmin",
    "roles/run.developer",
  ]
}
```

> **IAM binding note:** the workload module grants these roles with additive `google_project_iam_member` (`modules/stages/workload/main.tf`), not authoritative `google_project_iam_binding`. Each apply only adds the specified group/role pairs — it does not evict any other member already bound to the same role, so pre-existing manual bindings on the project are preserved.

### Step 4 — Plan and review

```bash
make plan-apps APP_ENV=dev APP_VARS=examples/dev.tfvars 2>&1 | grep -A5 "workload_payments"
```

Confirm the plan shows only new resource creation — no modifications to existing workload modules.

### Step 5 — Apply

```bash
terraform -chdir=envs/apps apply \
  -target=module.workload_payments \
  -var-file=../../examples/dev.tfvars
```

### Step 6 — Verify subnet access

```bash
# Confirm the service project is attached as a Shared VPC consumer
gcloud compute shared-vpc get-host-project PAYMENTS_PROJECT_ID

# List the subnets the service project can use
gcloud compute networks subnets list-usable \
  --project=PAYMENTS_PROJECT_ID \
  --format="table(subnetwork, ipCidrRange, region)"
```

### Step 7 — Verify IAM bindings

```bash
# Confirm the admin group has the expected roles
gcloud projects get-iam-policy PAYMENTS_PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:payments-admins@company.com" \
  --format="table(bindings.role)"
```

---

## Offboarding a Service Team

To remove a team's access:

1. Remove the `module.workload_{team}` block from `envs/apps/main.tf`
2. Run `terraform plan` and confirm only the workload module resources are in the destroy list
3. Apply the change

Before destroying, list all state resources to confirm scope:

```bash
terraform -chdir=envs/apps state list | grep workload_payments
```

Confirm with the team that no data buckets or databases need to be retained before the destroy.
