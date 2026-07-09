# Runbook: AWS Phase-0 Bootstrap and First-Time Stand-Up

**When to use:** You are standing up the AWS landing zone from zero — no AWS organization, no Terraform Cloud workspaces, no state. This is the AWS equivalent of the GCP [Quick Start](../guides/QUICK_START.md) bootstrap section, and it solves the same chicken-and-egg problem: the TFC workspace and AWS run credentials must exist **before** `terraform init` can store state.

**Time:** 2–4 hours for the first stand-up (mostly waiting on AWS account creation and manual console gates).
**Risk:** High for the management-account steps — you are operating with elevated, out-of-band credentials that bypass the guardrails the org root will later install. Every phase-0 action should be logged and the bootstrap identity revoked once CI takes over.
**Prerequisites:** See the out-of-band list below. You are comfortable with the [provider-selection model](../architecture/provider-selection.md) (one cloud = one root = one workspace) and the [cross-root contract](../architecture/adding-a-cloud.md) (downstream roots assume roles whose ARNs the org root publishes).

---

## Overview

The AWS landing zone is a **two-phase bootstrap**:

1. **Phase-1** (`envs/aws-organization`) creates the AWS organization, the SRA OU tree, the foundational member accounts, and the guardrails. It is the **producer** of the cross-root contract: it publishes `account_ids` and `account_role_arns` and has no `terraform_remote_state` data source, so it validates credential-free.
2. **Every downstream root** (`aws-security`, `aws-network`, `aws-identity`, `aws-shared-services`, `aws-backup`, `aws-workload-<env>`, `saas`) **reads** the org remote state and assumes a member-account role from `account_role_arns`.

But phase-1 itself cannot bootstrap the very things it needs to run: an AWS org to operate in, a TFC workspace to hold its state, and a run identity to authenticate with. Those are **phase-0** — created out-of-band, by hand, exactly once.

> **No cross-root `depends_on`.** Terraform has no dependency edge between roots. Cross-layer ordering is enforced entirely by **apply order** (this runbook) plus the fact that each downstream root reads the org remote state and will fail at plan time with a "no outputs" / "workspace has no state" error if `aws-organization` has not been applied yet.

---

## Prerequisites (out-of-band — cannot be Terraform-bootstrapped)

These three things must exist before you touch Terraform. None of them can be created by this repo:

- [ ] **An AWS management (payer) account** — either a brand-new account, or an existing standalone account you are willing to promote into the organization management account. This account becomes the org root; treat it as high-value and never run workloads in it.
- [ ] **A human/SSO administrator** with full access to that management account (root user for the very first steps, then an IAM admin or IAM Identity Center admin). AWS requires a human to accept the organization creation and to enable Identity Center — these are console actions, not API-only.
- [ ] **Terraform Cloud organization access** — an account in a TFC organization with permission to create workspaces and set workspace variables. You will need the TFC org name (it is supplied to every root as `var.tfc_organization` / the `cloud` backend `organization`).

---

## Phase-0: from zero state to a runnable `aws-organization` workspace

### Step 1 — Establish the management account

Either:

- **Create a new AWS account** to be the management account (recommended for a clean landing zone), or
- **Use an existing standalone account** that will become the org management account. If it already has resources, understand that the region-restriction SCP and other guardrails will apply org-wide once phase-1 runs.

Sign in as the account root user (or an admin) and confirm you can reach the AWS Organizations console. Do **not** create the organization by hand — `envs/aws-organization` does that. You only need the account to exist.

### Step 2 — Create a bootstrap identity for run #1

Run #1 of `aws-organization` needs AWS credentials in the management account **before** any of the roles this repo creates exist. Pick **one** of the two options:

**Option A — Static admin credentials (simplest, least secure).** Create a temporary IAM admin user (or use root, discouraged) in the management account and generate an access key. Set it as workspace environment variables (Step 4). Delete the key immediately after run #1.

**Option B — Hand-created OIDC / TFC dynamic-credentials role (recommended).** Manually create an IAM OIDC identity provider for Terraform Cloud (`app.terraform.io`) in the management account and a `terraform-bootstrap` role that trusts it, with an admin-scoped permission policy for run #1. Then drive it with TFC's native [dynamic credentials](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials/aws-configuration) — set these as **workspace environment variables**:

```text
TFC_AWS_PROVIDER_AUTH = true
TFC_AWS_RUN_ROLE_ARN  = arn:aws:iam::<mgmt-account-id>:role/terraform-bootstrap
```

> The exact OIDC provider thumbprint, the trust-policy `sub`/`aud` conditions, and the console click-path for creating the identity provider are **environment-specific** and change with TFC's published configuration — follow the HashiCorp doc linked above rather than a hard-coded snippet here. The `<mgmt-account-id>` is the 12-digit ID of the account from Step 1.

Whichever option you choose, this bootstrap identity is temporary. Once phase-1 has created the real `terraform-run` role (the ARN you pass as `terraform_run_role_arn`), migrate the workspace to that role and retire the bootstrap identity.

### Step 3 — Create the `aws-organization` TFC workspace

Create the workspace that will hold phase-1 state. In the Terraform Cloud UI (**Workspaces → New workspace**) or via the `tfe` CLI / `terraform` with the `tfe` provider:

1. **Name:** `aws-organization` (must match `backend.tf`, which hard-codes `workspaces { name = "aws-organization" }`).
2. **VCS connection:** connect it to this repository.
3. **Working directory:** `envs/aws-organization`.
4. **Execution mode:** Remote (or Agent for self-hosted runners).
5. Set the AWS auth workspace variables from Step 2 (`TFC_AWS_PROVIDER_AUTH` + `TFC_AWS_RUN_ROLE_ARN`, or the static-key env vars).

> **Exact CLI is environment-specific.** Whether you use the TFC UI, the `tfe` CLI, or a small `terraform` config using the `tfe` provider depends on your team's tooling. Any of them is fine — the workspace is out-of-band scaffolding, not part of the landing-zone code.

**Run #1 state note (the chicken-and-egg).** If you prefer, run #1 can execute with **local state** first (`terraform -chdir=envs/aws-organization init -backend=false` then a local apply with credentials in your shell), and then `terraform init` again **with** the `cloud` backend to **migrate** the local state into the newly created TFC workspace. This is the escape hatch for the case where you want the org created before the workspace exists. In most cases, though, creating the workspace first (this step) and letting TFC run #1 remotely is cleaner.

Supply the TFC org to the backend the same way every root does — via a gitignored `backend.hcl` or `TF_CLI_ARGS_init` (see `envs/aws-organization/backend.tf` for the two forms).

---

## Phase-0.5: org-wide default-VPC-deletion StackSet (out-of-band)

Every AWS account is created with a default VPC in every Region. A single Terraform root **cannot** fan out to every account and every Region to delete them — that is exactly the account-scoped "concern" problem (Convention 9): things that must exist (or not exist) in *every* account are handled per-layer, and brand-new accounts are covered by an **out-of-band CloudFormation StackSet**, not by Terraform in this repo.

**This is a documented manual step, not something Terraform does for you:**

1. In the management (or delegated CloudFormation) account, create a **service-managed StackSet** targeting the whole organization (or the OUs you care about), with **automatic deployment to new accounts enabled**.
2. The stack template deletes the default VPC (and its subnets, IGW, route tables) in each enabled Region.
3. Deploy it **after** the foundational accounts exist (i.e. after phase-1 apply), and leave auto-deployment on so future accounts are cleaned up when they join the org.

This links to the account-baseline concept: per-account defaults the declarative EC2 policy does **not** cover (default-VPC deletion, EBS-encryption-by-default, account S3 Block Public Access, password policy). The Terraform-managed slice of that baseline is applied per layer via `modules/aws/account-baseline`; the default-VPC deletion specifically stays a StackSet because it cannot be reliably done for every Region from one root.

---

## Who creates the downstream workspaces (decision)

**The downstream TFC workspaces and their TFC→AWS assume-role trust are created by a documented manual / `tfe`-CLI step — NOT by a `tfe` provider inside the `aws-organization` root.**

Putting a `tfe` provider in the AWS org root would pull a **fifth provider** into a root whose whole design point is provider-optionality (see [provider-selection](../architecture/provider-selection.md)). The org root declares exactly **one** provider (`aws`, management account). We do not compromise that to self-provision workspaces.

Instead, for each downstream root, create its workspace out-of-band (same mechanism as Step 3) and point its run identity at the corresponding member-account role. That role's ARN is published by the `aws-organization` root output **`account_role_arns`** — a map of member-account name → cross-account access role ARN. Set the downstream workspace's `TFC_AWS_RUN_ROLE_ARN` to the right entry:

| Downstream workspace | `account_role_arns` key | Notes |
|---|---|---|
| `aws-security` | `account_role_arns["security_tooling"]` | Delegated admin for GuardDuty / Security Hub / Config aggregator; also drives `log_archive` via an aliased provider. |
| `aws-network` | `account_role_arns["network"]` | Shared TGW / networking account. |
| `aws-identity` | `account_role_arns["shared_services"]` | Runs after Identity Center is delegated to Shared Services (see gate below). |
| `aws-shared-services` | `account_role_arns["shared_services"]` | Optional/gated shared platform services. |
| `aws-backup` | `account_role_arns["backup"]` | Centralized AWS Backup account. |
| `aws-workload-<env>` | `account_role_arns["<workload-account>"]` | One workspace per env via the `aws-workload-` prefix; key is the workload account name you added under `workload_accounts`. |
| `saas-<name>` | *(none — no AWS role)* | Supabase/Vercel only; reads AWS/GCP remote state for values but configures no AWS provider. |

> The account keys (`log_archive`, `security_tooling`, `network`, `shared_services`, `backup`, `forensics`) come from the `accounts` map in `envs/aws-organization/terraform.tfvars`. `account_role_arns` is keyed by exactly those names. Get the live values after phase-1 apply:
>
> ```bash
> terraform -chdir=envs/aws-organization output -json account_role_arns
> ```

You must also ensure each member-account role **trusts** the downstream workspace's TFC identity. That trust is part of creating the workspace + role wiring in this same out-of-band step — it is not managed by the org root.

---

## Full first-time stand-up order

Follow this order top to bottom. **Manual gates** are inline and must be completed before the next Terraform step will succeed. Remember: ordering is enforced by apply order and remote-state reads, not by any cross-root `depends_on`.

1. **Phase-0** — management account, bootstrap identity, `aws-organization` workspace (Steps 1–3 above).

2. **Apply `aws-organization`.** Copy `envs/aws-organization/terraform.tfvars.example` to `terraform.tfvars`, set real unique root emails for every account, the `terraform_run_role_arn`, `break_glass_role_arn`, and `log_archive_bucket_name`, then apply:

   ```bash
   terraform -chdir=envs/aws-organization apply
   ```

   This creates the org, the OU tree, the foundational accounts, and the guardrails, and publishes `account_ids` and `account_role_arns`.

3. **MANUAL GATE — IAM Identity Center.** In the **management account**, enable IAM Identity Center (console action — cannot be created by Terraform here), then **delegate administration to the Shared Services account**. The `aws-identity` root manages permission sets and assignments *after* this delegation exists; it cannot enable Identity Center for you.

4. **Create the downstream workspaces + role trust** (see the decision section above). For each of `aws-security`, `aws-network`, `aws-identity`, `aws-shared-services`, `aws-backup`, and each `aws-workload-<env>`, create the workspace out-of-band and set `TFC_AWS_RUN_ROLE_ARN` to the matching `account_role_arns[...]` value.

5. **Phase-0.5 — default-VPC-deletion StackSet.** Deploy the org-wide StackSet now that the accounts exist (see phase-0.5 section). Leave auto-deployment on.

6. **Apply `aws-security`.** Security tooling, log archive, org CloudTrail, GuardDuty, Security Hub, Config aggregator — the second half of the minimum governed baseline.

7. **Apply `aws-network`.** Shared networking (TGW, resolver, shared VPC constructs) in the network account.

8. **Apply `aws-identity`.** Permission sets and account assignments, now that Identity Center is delegated (gate in step 3).

9. **Apply `aws-shared-services`** *(optional / gated).* Shared platform services; apply only if you need them.

10. **Apply `aws-backup`.** Centralized AWS Backup vaults and plans.

11. **Apply `aws-workload-<env>`** *(per environment).* Select the env with `TF_WORKSPACE=aws-workload-<env>`. Each apply stands up that env's spoke VPC, workload roles, and per-account baseline. Repeat per environment.

12. **Apply `saas`** *(optional).* Supabase and/or Vercel only, gated by `enable_supabase` / `enable_vercel`. Configures no AWS provider.

> Each downstream root **reads the `aws-organization` remote state** for `account_role_arns` and other contract outputs. If you apply one before `aws-organization`, it fails at plan time. The minimum governed footprint is just `aws-organization` + `aws-security`; everything else is additive (see [provider-selection](../architecture/provider-selection.md#minimum-aws-footprint)).

---

## Teardown

Teardown is the **reverse** of the stand-up order (destroy workloads first, `aws-organization` last), and it carries a hard caveat: the Log Archive bucket uses **S3 Object Lock in COMPLIANCE mode**, which cannot be shortened or bypassed even by the root user — objects are immutable until their retention expires, so the bucket (and often the whole `log_archive` account) cannot be destroyed on demand.

The full reverse-order destroy procedure and the Object-Lock caveat are covered in `docs/runbooks/aws-teardown.md` (a later task). Do not attempt a blind `terraform destroy` across roots before reading it.

---

## See also

- [Quick Start](../guides/QUICK_START.md) — the GCP-side bootstrap this mirrors.
- [Provider Selection](../architecture/provider-selection.md) — why one cloud = one root = one workspace, and the combination matrix.
- [Adding a Cloud](../architecture/adding-a-cloud.md) — the cross-root contract (stable output keys, aliased foundational providers, credential-free remote state).
