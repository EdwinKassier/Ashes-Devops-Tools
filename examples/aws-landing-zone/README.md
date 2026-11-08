# AWS Landing Zone — Golden Path

A concise operator walkthrough for standing up the AWS SRA landing zone: the
config keys to set, and the order to apply the roots.

> **This directory is a documentation reference, not a deployable root.** There
> is no backend, no provider, and no `.tf` here — nothing to `init`. Every
> `envs/aws/*` input has a default: the values come from the committed
> **`config/landing-zone.yaml`**, which every root reads, so a VCS-driven
> Terraform Cloud run needs no tfvars. The `*.tfvars.example` files here show
> the **optional** explicit-variable form of each root's key inputs, with the
> config key each one falls back to. The fully commented templates live next to
> each root as `envs/aws/<root>/terraform.tfvars.example`.

## Before you start — bootstrap

The landing zone is a **two-phase bootstrap**. Phase-1 (`aws-organization`)
creates the org, accounts, and guardrails and cannot bootstrap the AWS org, TFC
workspace, and run identity it needs to run — those are **phase-0**, created
out-of-band exactly once.

Read and complete **[`docs/runbooks/aws-bootstrap.md`](../../docs/runbooks/aws-bootstrap.md)**
first. It covers: establishing the management account, creating a bootstrap
identity for run #1, creating the AWS TFC workspaces with `tfc-admin`, the
out-of-band default-VPC-deletion StackSet, and the manual IAM Identity Center
enablement gate.

Everything below assumes phase-0 is done.

## Step 1 — fill in `config/landing-zone.yaml`

Scaffold it with `make init` (`scripts/init-landing-zone.sh --clouds aws ...`)
or copy [`config/landing-zone.example.yaml`](../../config/landing-zone.example.yaml),
replace every placeholder, and **commit** it. No secrets go in it.

Precedence for every input: an explicit variable (tfvars, `TF_VAR_*`, or a TFC
workspace variable) wins over the config file, which wins over the built-in
default. An input that is still unset, or still an upstream placeholder, fails
the plan with a message naming the config key.

The two inputs every AWS root needs:

| Variable | Config key | Notes |
|----------|-----------|-------|
| `landing_zone_name` | `org.name` | 2-31 chars, lowercase letter first; the placeholders `ashes` / `my-org` are rejected |
| `tfc_organization` | `org.tfc.organization` | The TFC org that owns the workspaces; downstream roots read upstream state through it |

The other AWS keys, by the root that needs them:

| Config key | Used by | Notes |
|-----------|---------|-------|
| `aws.management_account_id` | `aws-organization`, `aws-security`, `aws-backup` | 12-digit ID, **quoted** |
| `aws.terraform_run_role_arn`, `aws.break_glass_role_arn` | `aws-organization` | Phase-0 management-account roles (runbook Step 2), carved out of every guardrail |
| `aws.log_archive_bucket_name` | `aws-organization`, `aws-security`, `aws-network` | One name for the whole estate (see the naming contract below) |
| `aws.accounts`, `aws.workload_accounts` | `aws-organization` | Real, unique, deliverable root emails (`example.com` is rejected) |
| `aws.workload_environments.<env>` | `tfc-admin`, `aws-organization`, `aws-workload` | `account_key` (required), optional `vpc_cidr` and `services`; one `aws-workload-<env>` workspace each |
| `aws.allowed_regions`, `aws.enabled_regions` | most AWS roots | Region-restriction SCP and the baselined regions |
| `aws.network.*`, `aws.identity.groups`, `aws.workload.*` | `aws-network`, `aws-identity`, `aws-workload` | Egress allowlist and spokes, name-based SSO assignments, app ingress |

Per-workspace values that are not in the config file go in a committed
`config/tfc-workspaces.yaml` (copy
[`config/tfc-workspaces.example.yaml`](../../config/tfc-workspaces.example.yaml));
`tfc-admin` sets them as workspace variables. Secrets go through `tfc-admin`
`workspace_variables` as sensitive variables, never into either file.

## Cross-root naming contract

Terraform has no cross-root dependency edge, so these values are threaded by
convention, not by a resource reference:

- `aws.log_archive_bucket_name` — protected by the `aws-organization`
  deny-tamper SCP, created by `aws-security`, and used by `aws-network`.
  `aws-workload` reads it from the `aws-security` contract (its remote state),
  so leave its `log_archive_bucket_name` override unset.
- The `aws-organization` **remote-state outputs** (`account_ids`,
  `account_role_arns`) — every downstream root reads these; ordering is enforced
  by apply order + remote-state reads, so `aws-organization` must be applied
  first.

## Stand-up order

Apply top to bottom, each as a Terraform Cloud run, with the gate rows done in place. This table follows [`docs/runbooks/aws-bootstrap.md`](../../docs/runbooks/aws-bootstrap.md#full-first-time-stand-up-order). The minimum governed
footprint is just steps 1–2 (`aws-organization` + `aws-security`); everything
after is additive. The last column links to the optional-override reference.

| # | Root | Purpose | Config it needs beyond `org.name` / `org.tfc.organization` | Reference |
|---|------|---------|-------------------------------------------------------|-----------|
| 1 | `aws-organization` | Org, OU tree, accounts, guardrails (the producer root) | `aws.management_account_id`, the two role ARNs, `aws.log_archive_bucket_name`, `aws.accounts` / `aws.workload_accounts` | [`aws-organization.tfvars.example`](./aws-organization.tfvars.example) |
| — | **MANUAL GATE** | Enable IAM Identity Center in the mgmt account, delegate to shared-services | — | Console action; blocks step 4. See runbook. |
| — | **tfc-admin pass 2** | Set `aws_organization_outputs_from_tfc = true` on `tfc-admin` and re-apply it. This writes the `TFC_AWS_*` dynamic-credential variables on every downstream workspace; without it step 2 has no AWS credentials | — | [Runbook step 4](../../docs/runbooks/aws-bootstrap.md#full-first-time-stand-up-order) |
| — | **Phase-0.5** | Deploy the org-wide default-VPC-deletion StackSet now that the accounts exist | — | [Runbook](../../docs/runbooks/aws-bootstrap.md#phase-05-org-wide-default-vpc-deletion-stackset-out-of-band) |
| 2 | `aws-security` | Security tooling, log archive, CloudTrail, GuardDuty, Security Hub, Config aggregator | `aws.management_account_id`, `aws.log_archive_bucket_name`. The KMS key admin, Config and aggregator roles and the Security Lake meta-store role are created or defaulted by the stage | [`aws-security.tfvars.example`](./aws-security.tfvars.example) |
| 3 | `aws-network` | TGW hub-spoke, IPAM, inspection/egress VPCs, resolver | `aws.log_archive_bucket_name`; `aws.network.*` to tune | [`aws-network.tfvars.example`](./aws-network.tfvars.example) |
| 4 | `aws-identity` | Identity Center permission sets + assignments | nothing more — needs the gate above; `aws.identity.groups` for assignments | [`aws-identity.tfvars.example`](./aws-identity.tfvars.example) |
| 5 | `aws-shared-services` | ACM Private CA + Secrets baseline *(gated, off by default)* | nothing more | [`aws-shared-services.tfvars.example`](./aws-shared-services.tfvars.example) |
| 6 | `aws-backup` | Centralized Backup vault + org plan + Vault Lock | `aws.management_account_id`. The backup and restore-testing roles are created by default | [`aws-backup.tfvars.example`](./aws-backup.tfvars.example) |
| 7 | `aws-workload` | Per-env spoke VPC + workload roles + account baseline | `aws.workload_environments.<env>.account_key` (tfc-admin sets `environment` on each `aws-workload-<env>` workspace) | [`aws-workload.tfvars.example`](./aws-workload.tfvars.example) |
| 8 | `saas` | Supabase and/or Vercel only *(optional, no AWS)* | `saas.*` — inputs become required per enabled feature | [`saas.tfvars.example`](./saas.tfvars.example) |

## How to run a root

Applies run in **Terraform Cloud**, against the workspaces `tfc-admin` created:
commit the config change and queue (or let VCS trigger) a run of the workspace,
review the plan there, then confirm the apply. Do not `terraform apply` an
`envs/*` root from a laptop; see the repo `CLAUDE.md` "State & Apply Rules".

A local plan is a read-only check that runs remotely in the workspace:

```bash
export TF_CLOUD_ORGANIZATION=<your TFC org>
export TF_WORKSPACE=aws-organization
terraform -chdir=envs/aws/organization init
terraform -chdir=envs/aws/organization plan
```

Phase-1 run #1 uses the bootstrap identity from the runbook; see its
"Full first-time stand-up order" for the exact sequence and the follow-up
passes (Config recorders, workload spoke attachments).

## See also

- [`docs/runbooks/aws-bootstrap.md`](../../docs/runbooks/aws-bootstrap.md) — phase-0 + full first-time stand-up order.
- [`docs/runbooks/aws-add-account.md`](../../docs/runbooks/aws-add-account.md) — add a workload account later.
- [`docs/runbooks/aws-teardown.md`](../../docs/runbooks/aws-teardown.md) — reverse-order destroy (mind the Object Lock caveat).
- [`docs/architecture/provider-selection.md`](../../docs/architecture/provider-selection.md) — one cloud = one root = one workspace, and the minimum AWS footprint.
- [`config/landing-zone.example.yaml`](../../config/landing-zone.example.yaml) — every config key, with comments.
