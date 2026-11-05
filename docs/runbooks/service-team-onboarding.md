# Runbook: Service Team Onboarding

**When to use:** A new application team needs their own GCP service project attached to the Shared VPC, with Workload Identity bindings for their workloads.

**Time:** 20–30 minutes.  
**Risk:** Low — adds new resources, does not modify existing spoke projects.  
**Prerequisites:** `envs/gcp/organization` and at least one `envs/gcp/workload` environment have been applied. The team's admin group email and billing account are known.

---

## Overview

Each service team gets:

1. A GCP project (created in `modules/gcp/stages/workload`)
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
terraform -chdir=envs/gcp/workload output host_project_id
terraform -chdir=envs/gcp/workload output subnets
```

The `subnets` output is a map. Each key is a subnet identifier; each value contains `region` and `self_link`.

### Step 3 — Add the team to the `service_teams` registry (config, not code)

Onboarding is a map entry in the environment's tfvars, not a new module block in `main.tf` (audit H10). The workload root iterates `var.service_teams` with `for_each`, so one entry creates one service project. Add the team to `examples/<env>.tfvars`:

```hcl
service_teams = {
  payments = {
    project_admin_group_email = "payments-admins@company.com"

    activate_apis = [
      "bigquery.googleapis.com",
      "run.googleapis.com",
      "storage.googleapis.com",
    ]

    # Additive per-role bindings for the admin group. Primitive roles
    # (owner/editor/viewer) and org/folder-level roles are rejected.
    project_admin_roles = [
      "roles/bigquery.dataEditor",
      "roles/storage.objectAdmin",
      "roles/run.developer",
    ]

    # Subnets to grant. Names are per-zone:
    #   <project_prefix>-<environment>-vpc-private-<region>-<zone>
    shared_vpc_subnets = {
      private = { region = "europe-west1", subnet_name = "ashes-dev-vpc-private-europe-west1-b" }
    }

    # enable_gke_network_user = true   # only for GKE projects
  }
}
```

The root wires `org_id`, `folder_id`, `billing_account`, and the Shared VPC host project from remote state and the host stage, so you set only the team-specific fields. `folder_id` and `billing_account` are normalised with `trimprefix`, so either the bare ID or the full resource name works.

> **IAM binding note:** the workload module grants these roles with additive `google_project_iam_member` (`modules/gcp/stages/workload/main.tf`), not authoritative `google_project_iam_binding`. Each apply only adds the specified group/role pairs — it does not evict any other member already bound to the same role, so pre-existing manual bindings on the project are preserved.

### Step 4 — Plan and review

```bash
make plan-gcp-workload APP_ENV=dev APP_VARS=examples/dev.tfvars 2>&1 | grep -A5 'service_team\["payments"\]'
```

Confirm the plan shows only new resource creation under `module.service_team["payments"]` — no modifications to existing teams.

### Step 5 — Apply

```bash
terraform -chdir=envs/gcp/workload apply \
  -target='module.service_team["payments"]' \
  -var-file=../../../examples/dev.tfvars
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

1. Delete the team's entry from the `service_teams` map in the environment's tfvars
2. Run `terraform plan` and confirm only that team's `module.service_team["<team>"]` resources are in the destroy list
3. Apply the change

Before destroying, list all state resources to confirm scope:

```bash
terraform -chdir=envs/gcp/workload state list | grep 'service_team\["payments"\]'
```

Confirm with the team that no data buckets or databases need to be retained before the destroy.
