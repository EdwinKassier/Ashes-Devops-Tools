# Sandbox E2E: real-apply tests

Every other test in this repo runs `terraform test` under `mock_provider`. Mocks prove that
a plan is shaped correctly. They cannot prove that the cloud accepts it. The sandbox E2E
suites close that gap. The 2026-11-05 audit flagged it as Maintainability (Critical):
"Nothing proves a real apply works".

| Suite | Composes (real modules) | Asserts (read back from the live API) |
|-------|-------------------------|----------------------------------------|
| [`tests/e2e/gcp`](../../tests/e2e/gcp/) | `gcp/governance/kms` (keyring) + CMEK key → `gcp/cloud-storage`; `gcp/network/vpc` → `gcp/network/subnet`; `gcp/data/secret-manager` | Bucket default encryption equals the created key; PAP enforced, UBLA, versioning, access logging; subnet CIDR, VPC attachment, Private Google Access; secret version round-trips |
| [`tests/e2e/aws`](../../tests/e2e/aws/) | `aws/data/kms-key` → `aws/data/log-archive-bucket` (Object Lock); `aws/network/vpc` (1 AZ, no NAT/IGW) | A canary object written with no encryption arguments comes back SSE-KMS with the created CMK, a bucket key, and GOVERNANCE retention; VPC/subnet CIDRs; S3 gateway endpoint is available; `default_tags` reach module resources |

Each suite is a small Terraform root (`main.tf`) and one `e2e.tftest.hcl` with
`command = apply`. Assertions read data sources that query the real API after apply, so
they are not echoes of the inputs. `terraform test` destroys everything at the end of the
file, pass or fail.

Two module constraints forced fixture choices, and both are intentional:

- `gcp/governance/kms` hard-codes `prevent_destroy` on its crypto keys, so the suite uses
  the module for the keyring only and declares the key itself. GCP keyrings cannot be
  deleted. Each run therefore leaves one empty keyring, which is free.
- `aws/data/log-archive-bucket` runs with `object_lock_mode = "GOVERNANCE"` and
  `retention_days = 1`, and sends its access logs to a separate sink bucket. COMPLIANCE
  mode, or AWS writing logs into the locked bucket, would make teardown impossible.

## Workflow

[`.github/workflows/sandbox-e2e.yml`](../../.github/workflows/sandbox-e2e.yml) triggers on:

- `workflow_dispatch`, with a `cloud` input of `all`, `gcp` or `aws`.
- A nightly `schedule` at 03:17 UTC.
- `pull_request`, but only when the PR carries the **`e2e`** label **and** its head branch
  is in this repository. Fork PRs never get cloud credentials. The workflow uses
  `pull_request`, never `pull_request_target`.

Workflow permissions are `{}`. Only the two cloud jobs get `id-token: write` and
`contents: read`. A concurrency group per cloud (`sandbox-e2e-gcp`, `sandbox-e2e-aws`) runs
one job at a time per sandbox with `cancel-in-progress: false`, because cancelling an apply
part-way is how orphans get made.

When a cloud's variables are unset, the preflight job **fails**, because a real-apply check
that never ran must not show green. The only quiet skip is a scheduled run with the repository
variable `REAL_CLOUD_CHECKS_OPT_OUT=true`, which you set only to acknowledge running without
E2E. A suite you asked for, through the dispatch input or the `e2e` label, always fails when
it is unconfigured.

### Teardown is guaranteed twice

1. `terraform test` destroys everything it applied.
2. An `if: always()` step runs [`cleanup-gcp.sh`](../../tests/e2e/scripts/cleanup-gcp.sh)
   or [`cleanup-aws.sh`](../../tests/e2e/scripts/cleanup-aws.sh). These scripts delete only
   what carries the run's mark:
   - **GCP:** resources labelled `e2e-run-id=<github.run_id>`, plus VPCs and subnets named
     `e2e-<run_id>-*`, because networks have no labels.
   - **AWS:** resources the Tagging API returns for `e2e-run-id=<github.run_id>`, plus KMS
     aliases named `alias/e2e-<run_id>-*`.

   The labels and tags are stamped by the provider (`default_labels` / `default_tags`), so
   every module resource carries them.

   If the script finds any leftover, the job fails. A broken teardown is never silently
   green.

Resource names include `<run_id>-<run_attempt>`, so a re-run never collides with an earlier
attempt.

## Enabling it

### 1. GCP sandbox project

1. Create a **dedicated, empty** project. Never use a landing-zone project, because the
   suite creates and deletes resources in it.
2. Link a billing account and enable `cloudkms`, `storage`, `compute` and `secretmanager`.
3. Create a service account, for example `e2e-runner@<project>.iam.gserviceaccount.com`.
   Grant it these roles **on that project only**:
   - `roles/cloudkms.admin`
   - `roles/storage.admin`
   - `roles/compute.networkAdmin`
   - `roles/secretmanager.admin`
   - `roles/serviceusage.serviceUsageConsumer`
4. Create a Workload Identity pool and an OIDC provider for
   `https://token.actions.githubusercontent.com`, with this attribute condition:

   ```text
   assertion.repository == '<owner>/<repo>' && assertion.sub == 'repo:<owner>/<repo>:environment:e2e-sandbox'
   ```

   Map `attribute.repository = assertion.repository`. Then grant
   `roles/iam.workloadIdentityUser` on the service account to
   `principalSet://iam.googleapis.com/<pool>/attribute.repository/<owner>/<repo>`.

### 2. AWS sandbox account

1. Use a **dedicated, empty** account, such as a `Sandbox` OU member. Never use a
   landing-zone account.
2. Add the IAM OIDC provider `token.actions.githubusercontent.com` with audience
   `sts.amazonaws.com`.
3. Create a role, for example `e2e-runner`, with this trust policy:
   - `StringEquals` on `token.actions.githubusercontent.com:aud` = `sts.amazonaws.com`
   - `StringEquals` on `token.actions.githubusercontent.com:sub` =
     `repo:<owner>/<repo>:environment:e2e-sandbox`
4. Give the role permissions scoped to the sandbox account:
   - KMS key and alias management
   - S3, including `s3:BypassGovernanceRetention`, `s3:PutBucketObjectLockConfiguration`
     and object tagging
   - EC2 VPC, subnet, route table, endpoint and flow-log management
   - `iam:GetRole`, `sts:GetCallerIdentity`, `tag:GetResources`

   The suite makes the runner role the key administrator and an S3-only key user. No
   other principal is involved.

### 3. GitHub

- Create the **`e2e-sandbox`** environment. The OIDC subject above depends on it.
  - Leave its deployment-branch policy unrestricted. Otherwise label-gated PR runs, which
    deploy from `refs/pull/<n>/merge`, are rejected.
  - Optionally add required reviewers. Note that nightly runs would then wait for approval.
- Set the **repository** variables listed in [CI Secrets & Variables](CI_SECRETS.md#sandbox-e2e).
  The preflight job has no environment and reads repository-level variables only.
- Create the `e2e` label.

No secrets are needed, because both clouds are keyless.

## Running locally

Use your own short-lived credentials (`gcloud auth application-default login` or
`AWS_PROFILE`/SSO) against the **same sandbox**:

```bash
make e2e-gcp E2E_GCP_PROJECT=<sandbox-project> [E2E_GCP_REGION=europe-west2]
make e2e-aws E2E_AWS_REGION=eu-west-2            # uses the ambient AWS credentials
```

Each target uses a fresh `RUN_ID` (the epoch seconds) and runs the matching cleanup script
afterwards. The CLAUDE.md rule against local `terraform apply` covers the landing-zone
roots. It does not cover these disposable fixtures, but they must only ever point at the
sandbox.

## Cost guardrails (< $1 per run)

| Cloud | What is billed | Approximate cost per run |
|-------|----------------|--------------------------|
| GCP | One software KMS key version: $0.06/month prorated, destroyed with a 1-day schedule. Empty buckets, a VPC with no VMs, and one secret version for a few minutes. Flow logs only bill for traffic, and there is none. | < $0.01 |
| AWS | One CMK: $1/month prorated hourly, scheduled for deletion with the 7-day minimum window. Even if the pending window is billed, that is about $0.23. A few KB in S3, gateway endpoint (free), flow logs (no traffic). No NAT gateway, no IGW, no interface endpoints. | < $0.25 |

Keep it that way:

- Do not add NAT gateways, interface endpoints, compute or databases to these suites. Those
  belong in their own opt-in suite with its own budget.
- Put a billing budget alert on the sandbox, for example $10/month.
- Each job has `timeout-minutes: 45`, and the concurrency groups prevent pile-ups.

## Known residue (by design)

- **GCP keyrings:** one empty keyring per run, named `e2e-<run_id>-<attempt>`. GCP has no
  delete API for keyrings, and they cost nothing.
- **GCP bucket names:** `gcp/cloud-storage` derives its logs and access-log bucket names
  from the project ID. Each sandbox project therefore runs one GCP suite at a time, which
  the concurrency group enforces.
- **AWS KMS keys:** keys stay in `PendingDeletion` for 7 days after a run. The cleanup
  script ignores them.
