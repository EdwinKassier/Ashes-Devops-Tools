# Runbook: Service Team Onboarding

**When to use:** A new application team needs their own GCP service project attached to the Shared VPC, with Workload Identity bindings for their workloads.

**Time:** 20–30 minutes.  
**Risk:** Low — adds new resources, does not modify existing spoke projects.  
**Prerequisites:** `envs/organization` and at least one `envs/apps` environment have been applied. The team's GitHub repository and service account email are known.

---

## Overview

Each service team gets:

1. A GCP project (created in `modules/stages/workload`)
2. Shared VPC attachment (the team's VMs use the existing host network)
3. IAM bindings for their service accounts
4. A WIF binding so their GitHub Actions / workloads can call GCP APIs without keys

---

## Steps

### Step 1 — Gather team information

Before starting, collect:

| Item | Example |
|------|---------|
| Team name (short, lowercase) | `payments` |
| GitHub repo (for WIF) | `my-org/payments-service` |
| Service account email | `payments-sa@payments-proj.iam.gserviceaccount.com` |
| Required IAM roles on their project | `["roles/bigquery.dataEditor", "roles/storage.objectAdmin"]` |
| Required subnets (from host project) | `["private", "database"]` |

### Step 2 — Add a workload module call in `envs/apps/main.tf`

```hcl
module "workload_payments" {
  source = "../../modules/stages/workload"

  project_id     = var.project_id
  project_prefix = var.project_prefix
  environment    = var.environment

  team_name = "payments"

  # IAM roles granted on the workload project (authoritative per-role)
  project_admin_roles = [
    "roles/bigquery.dataEditor",
    "roles/storage.objectAdmin",
  ]

  # Subnets from the Shared VPC this project can use
  shared_vpc_subnets = [
    module.host.subnets["private"].self_link,
    module.host.subnets["database"].self_link,
  ]

  # Service account that workloads run as
  workload_service_account_email = "payments-sa@payments-proj.iam.gserviceaccount.com"
}
```

> **IAM binding note:** `google_project_iam_binding` is **authoritative per role** — it will remove any member not listed from that role. If the team's project already has manual bindings, they must be imported into state first. Prefer adding new roles rather than modifying existing entries.

### Step 3 — Plan and review

```bash
make plan-apps APP_ENV=dev APP_VARS=examples/dev.tfvars 2>&1 | grep -A3 "workload_payments"
```

Confirm the plan shows only new resource creation with no unexpected modifications.

### Step 4 — Apply

```bash
terraform -chdir=envs/apps apply \
  -target=module.workload_payments \
  -var-file=examples/dev.tfvars
```

### Step 5 — Set up WIF for the team's GitHub Actions

Add a WIF binding for the team's repository in the bootstrap module. In `envs/organization/main.tf`, update the `additional_repositories` list (or equivalent variable) in `module.bootstrap`:

```hcl
module "bootstrap" {
  # ...
  additional_github_repos = [
    "my-org/payments-service",   # add this
  ]
}
```

Apply the organization root:

```bash
terraform -chdir=envs/organization apply -target=module.bootstrap
```

The team can now use the following in their GitHub Actions workflows:

```yaml
- uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: ${{ vars.WORKLOAD_IDENTITY_PROVIDER }}
    service_account: payments-sa@payments-proj.iam.gserviceaccount.com
```

### Step 6 — Verify subnet access

Confirm the service project is attached as a Shared VPC consumer:

```bash
gcloud compute shared-vpc get-host-project PAYMENTS_PROJECT_ID

# List effective subnets the service project can use
gcloud compute networks subnets list-usable \
  --project=PAYMENTS_PROJECT_ID \
  --format="table(subnetwork, ipCidrRange, region)"
```

### Step 7 — Verify WIF binding

```bash
# List WIF pool providers and confirm the team's repo is in the attribute condition
gcloud iam workload-identity-pools providers describe github \
  --workload-identity-pool=github-pool \
  --location=global \
  --project=ADMIN_PROJECT_ID \
  --format="value(attributeCondition)"
```

---

## Offboarding a Service Team

To remove a team's access:

1. Remove the `module.workload_{team}` block from `envs/apps/main.tf`
2. Run `terraform plan` and confirm only the workload module resources are destroyed
3. Remove the team's repo from `additional_github_repos` in the bootstrap module
4. Apply both changes

> **State tip:** Before destroying, run `terraform state list | grep workload_{team}` to see all resources that will be removed. Confirm with the team that no data buckets or databases need to be retained before the destroy.
