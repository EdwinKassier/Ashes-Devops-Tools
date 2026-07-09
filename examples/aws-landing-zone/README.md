# AWS Landing Zone — Golden Path

A concise operator walkthrough for standing up the AWS SRA landing zone: the
exact order to apply the roots, and the minimal REQUIRED tfvars for each one.

> **This directory is a documentation reference, not a deployable root.** There
> is no backend, no provider, and no `.tf` here — nothing to `init`. The
> `*.tfvars.example` files list only the inputs that have **no default** (i.e.
> are REQUIRED) for each root, so you can see the minimum surface at a glance.
> The canonical, fully-commented templates live next to each root as
> `envs/<root>/terraform.tfvars.example` — copy **those** to
> `envs/<root>/terraform.tfvars` for a real apply.

## Before you start — bootstrap

The landing zone is a **two-phase bootstrap**. Phase-1 (`aws-organization`)
creates the org, accounts, and guardrails and cannot bootstrap the AWS org, TFC
workspace, and run identity it needs to run — those are **phase-0**, created
out-of-band exactly once.

Read and complete **[`docs/runbooks/aws-bootstrap.md`](../../docs/runbooks/aws-bootstrap.md)**
first. It covers: establishing the management account, creating a bootstrap
identity for run #1, creating the `aws-organization` TFC workspace, the
out-of-band default-VPC-deletion StackSet, who creates the downstream
workspaces, and the manual IAM Identity Center enablement gate.

Everything below assumes phase-0 is done.

## Cross-root naming contract

Two strings must be **identical** across the roots that reference them, because
Terraform has no cross-root dependency edge — the value is threaded by
convention, not by a resource reference:

- `log_archive_bucket_name` — shared by `aws-organization` (deny-tamper SCP),
  `aws-security` (creates the bucket), `aws-network`, and `aws-workload`.
- The `aws-organization` **remote-state outputs** (`account_ids`,
  `account_role_arns`) — every downstream root reads these; ordering is enforced
  by apply order + remote-state reads, so `aws-organization` must be applied
  first.

## Stand-up order

Apply top to bottom. The minimum governed footprint is just steps 1–2
(`aws-organization` + `aws-security`); everything after is additive. Each row
links to the minimal-input reference file in this directory.

| # | Root | Purpose | Minimal REQUIRED tfvars | Notes |
|---|------|---------|-------------------------|-------|
| 1 | `aws-organization` | Org, OU tree, accounts, guardrails (the producer root) | `terraform_run_role_arn`, `break_glass_role_arn`, `log_archive_bucket_name` (+ real unique account emails) | [`aws-organization.tfvars.example`](./aws-organization.tfvars.example) |
| — | **MANUAL GATE** | Enable IAM Identity Center in the mgmt account, delegate to shared-services | — | Console action; blocks step 4. See runbook. |
| 2 | `aws-security` | Security tooling, log archive, CloudTrail, GuardDuty, Security Hub, Config aggregator | `log_archive_bucket_name`, `key_admin_arn`, `config_role_arn`, `aggregator_role_arn` | [`aws-security.tfvars.example`](./aws-security.tfvars.example) |
| 3 | `aws-network` | TGW hub-spoke, IPAM, inspection/egress VPCs, resolver | `log_archive_bucket_name` | [`aws-network.tfvars.example`](./aws-network.tfvars.example) |
| 4 | `aws-identity` | Identity Center permission sets + assignments | *(none required)* — needs the gate above | [`aws-identity.tfvars.example`](./aws-identity.tfvars.example) |
| 5 | `aws-shared-services` | ACM Private CA + Secrets baseline *(gated, off by default)* | *(none required)* | [`aws-shared-services.tfvars.example`](./aws-shared-services.tfvars.example) |
| 6 | `aws-backup` | Centralized Backup vault + org plan + Vault Lock | `backup_role_arn`, `restore_testing_role_arn` | [`aws-backup.tfvars.example`](./aws-backup.tfvars.example) |
| 7 | `aws-workload` | Per-env spoke VPC + workload roles + account baseline | `workload_account_key`, `log_archive_bucket_name`, `config_role_arn` | [`aws-workload.tfvars.example`](./aws-workload.tfvars.example) — one workspace per env (`TF_WORKSPACE=aws-workload-<env>`) |
| 8 | `saas` | Supabase and/or Vercel only *(optional, no AWS)* | *(none unconditionally)* — inputs become required per enabled feature | [`saas.tfvars.example`](./saas.tfvars.example) |

## How to apply a root

For each root, copy the env template (not the reference file here), fill in the
REQUIRED inputs, and apply. Example for phase-1:

```bash
cp envs/aws-organization/terraform.tfvars.example envs/aws-organization/terraform.tfvars
# edit terraform.tfvars: set the two role ARNs, log_archive_bucket_name, and
# real unique root emails for every account
terraform -chdir=envs/aws-organization apply
```

> **Apply happens in Terraform Cloud**, not locally, against these roots. Local
> `terraform plan` is a read-only check; never `terraform apply` locally against
> an `envs/*` root. See the repo `CLAUDE.md` "State & Apply Rules".

## Per-root REQUIRED inputs (summary)

Derived directly from each root's `variables.tf` — a variable with no `default`
is REQUIRED. Roots not listed have no unconditionally-required inputs.

- **aws-organization** — `terraform_run_role_arn`, `break_glass_role_arn`,
  `log_archive_bucket_name`. (Also override the placeholder account emails.)
- **aws-security** — `log_archive_bucket_name`, `key_admin_arn`,
  `config_role_arn`, `aggregator_role_arn`. (`meta_store_manager_role_arn`
  becomes required when `enable_security_lake = true`, the default.)
- **aws-network** — `log_archive_bucket_name`.
- **aws-identity** — none (needs the Identity Center gate first).
- **aws-shared-services** — none (features off by default).
- **aws-backup** — `backup_role_arn`, `restore_testing_role_arn`.
- **aws-workload** — `workload_account_key`, `log_archive_bucket_name`,
  `config_role_arn`. (`kms_key_arn` is effectively required — Session Manager
  needs a CMK.)
- **saas** — none unconditionally; each enabled feature (`enable_supabase` /
  `enable_vercel`) makes its own inputs required, and the matching API token
  (`SUPABASE_ACCESS_TOKEN` / `VERCEL_API_TOKEN`) must be exported.

## See also

- [`docs/runbooks/aws-bootstrap.md`](../../docs/runbooks/aws-bootstrap.md) — phase-0 + full first-time stand-up order.
- [`docs/runbooks/aws-add-account.md`](../../docs/runbooks/aws-add-account.md) — add a workload account later.
- [`docs/runbooks/aws-teardown.md`](../../docs/runbooks/aws-teardown.md) — reverse-order destroy (mind the Object Lock caveat).
- [`docs/architecture/provider-selection.md`](../../docs/architecture/provider-selection.md) — one cloud = one root = one workspace, and the minimum AWS footprint.
