# VPC Service Controls Example

Creates a VPC-SC service perimeter protecting BigQuery, Cloud Storage, and Secret
Manager in a single project. Starts in **dry-run mode** — violations are logged to
Cloud Audit Logs but traffic is NOT blocked. Switch to enforced mode once you have
validated that no legitimate traffic is caught.

## What this creates

| Resource | Notes |
|----------|-------|
| `google_access_context_manager_service_perimeter` | Dry-run perimeter around `protected_projects` |
| Ingress policy | Lets one GitHub repository's federated identities (a WIF `principalSet` in `identities`) call BigQuery and Cloud Storage in the protected project |
| Restricted services | BigQuery, Cloud Storage, Secret Manager |

## How the ingress rule is built

- `identities` names who may cross the perimeter: here the WIF `principalSet`
  for one GitHub repository ID. Leave `identity_type` null when you list
  identities; avoid `ANY_IDENTITY` for CI. If the workflow impersonates a
  service account (the repo's usual pattern), list `serviceAccount:<email>`
  instead, because that is the identity the protected API sees.
- `sources` names where the request comes from. Only an access level (`"*"`
  for any network origin) or a project, folder, organization or VPC network is
  valid. A Workload Identity pool is not a source.
- `resources` is required and names the perimeter projects the rule opens
  (`projects/<number>`, or `"*"` for all of them).

See Google's [ingress and egress rules](https://docs.cloud.google.com/vpc-service-controls/docs/ingress-egress-rules)
and [supported identities](https://docs.cloud.google.com/vpc-service-controls/docs/supported-identities).

## Prerequisites

- An **Access Policy**. An organization has one organization-level policy;
  scoped policies (limited to a folder or project) can exist alongside it.
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

# 5. Monitor for violations (see "Finding violations" below)

# 6. When confident, switch to enforced mode:
#    Set enable_dry_run = false in main.tf, then re-apply
```

## Finding violations

VPC-SC writes violations to the **policy** audit log of the protected project,
with `VpcServiceControlAuditMetadata` in `protoPayload.metadata`. On these
entries, `protoPayload.serviceName` is the service that was called (for example
`storage.googleapis.com`), not `accesscontextmanager.googleapis.com`. Dry-run
violations also carry `metadata.dryRun = true`:

```bash
gcloud logging read --project=<protected-project-id> --freshness=7d '
  logName:"cloudaudit.googleapis.com%2Fpolicy"
  AND protoPayload.metadata."@type"="type.googleapis.com/google.cloud.audit.VpcServiceControlAuditMetadata"
  AND protoPayload.metadata.dryRun=true'
```

Drop the `dryRun` line to see enforced denials after the switch, or add
`AND protoPayload.serviceName="storage.googleapis.com"` to narrow to one
service. See Google's [VPC-SC troubleshooting](https://docs.cloud.google.com/vpc-service-controls/docs/troubleshooting)
and [dry-run mode](https://docs.cloud.google.com/vpc-service-controls/docs/dry-run-mode) pages.

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
