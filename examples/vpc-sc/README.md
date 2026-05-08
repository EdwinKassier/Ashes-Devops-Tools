# VPC Service Controls Example

Creates a VPC-SC service perimeter protecting BigQuery, Cloud Storage, and Secret
Manager in a single project. Starts in **dry-run mode** — violations are logged to
Cloud Audit Logs but traffic is NOT blocked. Switch to enforced mode once you have
validated that no legitimate traffic is caught.

## What this creates

| Resource | Notes |
|----------|-------|
| `google_access_context_manager_service_perimeter` | Dry-run perimeter around `protected_projects` |
| Ingress policy | Allows Workload Identity Federation from a specific WIF pool |
| Restricted services | BigQuery, Cloud Storage, Secret Manager |

## Prerequisites

- An **Access Policy** for the organization. A single org can have only one.
  - Use `create_access_policy = true` if you don't have one yet.
  - Otherwise get the existing policy ID: `gcloud access-context-manager policies list --organization=<org-id>`
- The **numeric project number** (not the project ID) for every project you want
  to protect: `gcloud projects describe <id> --format='value(projectNumber)'`
- The `accesscontextmanager.googleapis.com` API enabled in the admin project.

## Usage

```bash
# 1. Edit main.tf — set organization_id, access_policy_name, and protected_projects
# 2. Initialise
terraform -chdir=examples/vpc-sc init

# 3. Plan (reads live Access Policy state — requires GCP credentials)
terraform -chdir=examples/vpc-sc plan

# 4. Apply in dry-run mode first
terraform -chdir=examples/vpc-sc apply

# 5. Monitor for violations (dry-run logs to Cloud Audit Logs under protoPayload.status)
# gcloud logging read 'protoPayload.serviceName="accesscontextmanager.googleapis.com" protoPayload.status.code=7'

# 6. When confident, switch to enforced mode:
#    Set enable_dry_run = false in main.tf, then re-apply
```

## Dry-run → enforcement workflow

1. Apply with `enable_dry_run = true`
2. Watch Cloud Audit Logs for 1–2 weeks
3. Add ingress/egress policies for any legitimate cross-perimeter traffic
4. Set `enable_dry_run = false` and apply

Never skip straight to enforced mode — a misconfigured perimeter will block
legitimate GCP API traffic and can cause service outages.

## Customisation

| Parameter | What to change |
|-----------|---------------|
| `restricted_services` | Add any GCP API that processes sensitive data |
| `ingress_policies` | Add CI/CD service accounts, on-prem VPN sources, etc. |
| `egress_policies` | Add if projects inside the perimeter need to write to external destinations |
| `enable_dry_run` | Set `false` once the ingress/egress policies are fully validated |
