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

> **App deploys (WIF):** to deploy an application from a team's GitHub repository, do not touch the bootstrap (infrastructure) WIF pool. Add a `services` entry under `gcp.environments.<env>` in `config/landing-zone.yaml` (the `app_services` input) with `github = { repository_id = "<numeric id>" }` in the `gcp-workload-<env>` workspace. It creates a per-service deploy SA bound to an app-only WIF pool in the env host project. See [`../guides/deploying-a-service.md`](../guides/deploying-a-service.md). To run the service in the team's own project, set `service_team` on it (Step 3a).

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

### Step 3 — Add the team to `config/landing-zone.yaml` (config, not code)

Onboarding is a map entry in the environment's block of the config file, not a new module block in `main.tf`. The workload root reads `gcp.environments.<env>.service_teams` and creates one service project per entry. Add the team under the environment it belongs to:

```yaml
gcp:
  environments:
    dev:
      service_teams:
        payments:
          project_admin_group_email: payments-admins@company.com
          activate_apis:
            - bigquery.googleapis.com
            - run.googleapis.com
            - storage.googleapis.com
          # Additive per-role bindings for the admin group. Primitive roles
          # (owner/editor/viewer) and org/folder-level roles are rejected.
          project_admin_roles:
            - roles/bigquery.dataEditor
            - roles/storage.objectAdmin
            - roles/run.developer
          # Subnets to grant. Names are per-zone:
          #   <project_prefix>-<environment>-vpc-private-<region>-<zone>
          shared_vpc_subnets:
            private: {region: europe-west1, subnet_name: ashes-dev-vpc-private-europe-west1-b}
          # enable_gke_network_user: true   # only for GKE projects
```

The schema (`config/landing-zone.schema.json`) validates the entry in your editor and in CI. The root wires `org_id`, `folder_id`, `billing_account`, and the Shared VPC host project from remote state and the host stage, so you set only the team-specific fields. `folder_id` and `billing_account` are normalised with `trimprefix`, so either the bare ID or the full resource name works. An explicit `service_teams` workspace variable replaces the config entry for that workspace.

> **IAM binding note:** the workload module grants these roles with additive `google_project_iam_member` (`modules/gcp/stages/workload/main.tf`), not authoritative `google_project_iam_binding`. Each apply only adds the specified group/role pairs — it does not evict any other member already bound to the same role, so pre-existing manual bindings on the project are preserved.

### Step 3a — Deploy a service into the team project (optional)

By default a service runs in the environment host project. To run it in the team's project, point it at the team by key:

```yaml
gcp:
  environments:
    dev:
      services:
        api:
          service_team: payments      # a key of service_teams above
          github: {repository_id: "123456789"}
```

The environment stage resolves the project ID and number from `module.environment.module.service_team["payments"]`, so there is no project ID to copy. The service's Artifact Registry repo, runtime and deploy service accounts, Cloud Run service, Cloud SQL, alert policies and Pub/Sub then live in the team project. The app-deploy WIF pool stays in the host project; the deploy SA in the team project is bound to it.

What the apply adds for such a service, beyond the per-service resources:

- the team project gets `run.googleapis.com`, `artifactregistry.googleapis.com`, `iam.googleapis.com`, `containerscanning.googleapis.com` and `monitoring.googleapis.com` (plus `sqladmin`, `secretmanager`, `pubsub` when the service uses them), merged into the team's `activate_apis`;
- the team project's Cloud Run service agent (`service-<project number>@serverless-robot-prod.iam.gserviceaccount.com`) gets `roles/compute.networkUser` on the Shared VPC subnet the service attaches to (the environment's first private subnet, or the service's `subnetwork_id`) and `roles/compute.networkViewer` on the host project. Direct VPC egress fails without both.

Shared VPC grants are created once per team (and once per subnet), not once per service, so removing one service never revokes a sibling's access. The root groups them by the `service_team` name.

Secrets: a short `secrets.<ENV>.secret` id is looked up in the **team project**. Secrets that live in the host project (including the SaaS bridge secret) must be referenced by full name, `projects/<host project id>/secrets/<name>`; the runtime SA is then granted `secretAccessor` on exactly that secret.

CMEK: if you set `artifact_registry_kms_key_name` or `pubsub_kms_key_name`, the Artifact Registry and Pub/Sub service agents of **each team project** need `roles/cloudkms.cryptoKeyEncrypterDecrypter` on the key, in addition to the host project's. Grant it before the first apply that creates the team's repos or topics.

Rules:

- `service_team` must name a declared team. An unknown key fails the plan with an error naming the key. Declare the team first.
- Do not combine `service_team` with an explicit `project_id` / `project_number`; use one or the other.
- The first apply creates the team project and then the service in one run. If a revision fails to roll out because the service agent does not exist yet, re-run the apply once the Cloud Run API is enabled in the team project.
- Moving an existing service between the host project and a team project recreates its project-scoped resources (service accounts, Cloud Run, registry). Plan the move; do not edit an applied service in place without reading the plan.
- New scaffolds (`make init`) start with a `platform` team and an example `api` service pointing at it. Replace the placeholder admin group and `subnet_name` before the first apply.

### Step 4 — Open a PR and review the plan

Commit the YAML change on a branch and open a pull request. CI runs the format, schema and policy checks, and Terraform Cloud posts a speculative plan for `gcp-workload-<env>` on the PR (the workspaces trigger on `config/**`). To preview the same plan locally (read-only):

```bash
make plan-gcp-workload APP_ENV=dev 2>&1 | grep -A5 'service_team\["payments"\]'
```

Confirm the plan shows only new resource creation under `module.environment.module.service_team["payments"]` — no modifications to existing teams.

### Step 5 — Merge and apply in Terraform Cloud

Merge the PR. The merge queues a run on `gcp-workload-<env>`; review the plan in Terraform Cloud and approve the apply. Never run `terraform apply` locally; if the run needs recovery, see [apply-recovery.md](apply-recovery.md).

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

1. Delete the team's entry from `gcp.environments.<env>.service_teams` in `config/landing-zone.yaml` and open a PR
2. Read the speculative plan on the PR and confirm only that team's `module.environment.module.service_team["<team>"]` resources are in the destroy list
3. Merge, then approve the apply in Terraform Cloud

Before destroying, list all state resources to confirm scope:

```bash
TF_WORKSPACE=gcp-workload-dev terraform -chdir=envs/gcp/workload state list | grep 'service_team\["payments"\]'
```

Confirm with the team that no data buckets or databases need to be retained before the destroy.
