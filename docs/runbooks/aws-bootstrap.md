# Runbook: AWS Phase-0 Bootstrap and First-Time Stand-Up

**When to use:** You are standing up the AWS landing zone from zero — no AWS organization, no Terraform Cloud workspaces, no state. This is the AWS equivalent of the GCP [Quick Start](../guides/QUICK_START.md) bootstrap section, and it solves the same chicken-and-egg problem: the TFC workspace and AWS run credentials must exist **before** `terraform init` can store state.

**Time:** about 1–2 weeks for a first production stand-up, mostly account creation, the Identity Center console gate, IAM propagation and reviewing each layer's first plan. A sandbox run-through with the shipped phase-0 template takes about a day.
**Risk:** High for the management-account steps — you are operating with elevated, out-of-band credentials that bypass the guardrails the org root will later install. Every phase-0 action should be logged and the bootstrap identity revoked once CI takes over.
**Prerequisites:** See the out-of-band list below. You are comfortable with the [provider-selection model](../architecture/provider-selection.md) (one cloud = one root = one workspace) and the [cross-root contract](../architecture/adding-a-cloud.md) (downstream roots assume roles whose ARNs the org root publishes).

---

## Overview

The AWS landing zone is a **two-phase bootstrap**:

1. **Phase-1** (`envs/aws/organization`) creates the AWS organization, the SRA OU tree, the foundational member accounts, and the guardrails. It is the **producer** of the cross-root contract: it publishes `account_ids` and `account_role_arns` and has no `terraform_remote_state` data source, so it validates credential-free.
2. **Every downstream root** (`aws-security`, `aws-network`, `aws-identity`, `aws-shared-services`, `aws-backup`, `aws-workload-<env>`) **reads** the org remote state. It authenticates **directly into its own member account** through TFC dynamic credentials for that account's `tfc-plan` / `tfc-apply` role. Phase-1 creates those roles (the [TFC OIDC baseline](#member-account-credentials-tfc-oidc-baseline)) and publishes them as `tfc_plan_role_arns` / `tfc_apply_role_arns`. `saas` configures no AWS provider.

> **Credential model.** Management-account credentials are used only by `aws-organization` and by the management-account *default* provider of `aws-security` and `aws-backup`. Those two roots own org-level resources: the org CloudTrail, delegated-admin registrations and the org backup policy. No other workspace receives a management-account principal. A speculative PR plan runs with the read-only `tfc-plan` role of its own member account.

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

Sign in as the account root user (or an admin) and confirm you can reach the AWS Organizations console. Do **not** create the organization by hand — `envs/aws/organization` does that. You only need the account to exist.

### Step 2 — Create a bootstrap identity for run #1

Run #1 of `aws-organization` needs AWS credentials in the management account **before** any of the roles this repo creates exist. Pick **one** of the two options:

**Option A — Static admin credentials (simplest, least secure).** Create a temporary IAM admin user (or use root, discouraged) in the management account and generate an access key. Set it as workspace environment variables (Step 4). Delete the key immediately after run #1.

**Option B — OIDC / TFC dynamic-credentials roles (recommended).** Deploy the shipped template [`templates/aws/bootstrap/phase0-management.yaml`](../../templates/aws/bootstrap/phase0-management.yaml) as one CloudFormation stack in the management account. It creates exactly the resources below, plus the MFA-gated `OrganizationBreakGlass` role, and outputs the ARNs that `aws.terraform_run_role_arn` and `aws.break_glass_role_arn` need:

```bash
aws cloudformation deploy --stack-name ashes-phase0 \
  --template-file templates/aws/bootstrap/phase0-management.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides TfcOrganization=<tfc-org> TfcProject=<prefix>aws \
    BreakGlassTrustedPrincipalArn=arn:aws:iam::<mgmt-account-id>:user/break-glass
aws cloudformation describe-stacks --stack-name ashes-phase0 --query 'Stacks[0].Outputs'
```

After aws-organization has created the dedicated `aws-security` / `aws-backup` roles, update the stack with `TrustSecurityAndBackup=false`. Keep `aws_overrides.create_break_glass` unset (false) in aws-security: the break-glass role belongs to this phase-0 stack, and the aws-security management role is deliberately denied access to it. To create the resources by hand instead, in the **management account** create:

1. An IAM OIDC identity provider for `https://app.terraform.io` with audience `aws.workload.identity`.
2. A **plan** role, e.g. `tfc-mgmt-plan`, with `ReadOnlyAccess`, and an **apply** role, e.g. `tfc-mgmt-apply`, with an admin-scoped policy. Each trusts only the management-account workspaces, for its own run phase:

```json
{
  "Effect": "Allow",
  "Principal": { "Federated": "arn:aws:iam::<mgmt-account-id>:oidc-provider/app.terraform.io" },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "app.terraform.io:aud": "aws.workload.identity",
      "app.terraform.io:sub": [
        "organization:<tfc-org>:project:<project>:workspace:aws-organization:run_phase:apply",
        "organization:<tfc-org>:project:<project>:workspace:aws-security:run_phase:apply",
        "organization:<tfc-org>:project:<project>:workspace:aws-backup:run_phase:apply"
      ]
    }
  }
}
```

In the plan role, use `run_phase:plan` in place of `run_phase:apply`. Never wildcard the organization.

> **The shared role is temporary for `aws-security` / `aws-backup`.** The first `aws-organization` apply creates a dedicated least-privilege plan/apply pair for each of them in the management account: `tfc-mgmt-aws-security-*` and `tfc-mgmt-aws-backup-*`, from [`tfc-management-roles`](../../modules/aws/iam/tfc-management-roles/README.md), with `enable_tfc_management_roles` defaulting to true. With `aws_organization_outputs_from_tfc = true`, `tfc-admin` then binds each workspace to its own pair. Once both workspaces have run on their dedicated roles, remove their two `sub` entries from the phase-0 trust above, so only `aws-organization` can reach the management admin role. The dedicated apply roles cannot assume `OrganizationAccountAccessRole`, change accounts or OUs, or edit any `tfc-mgmt-*` role. Then drive the roles with TFC's native [dynamic credentials](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials/aws-configuration) by setting these **workspace environment variables**:

```text
TFC_AWS_PROVIDER_AUTH  = true
TFC_AWS_PLAN_ROLE_ARN  = arn:aws:iam::<mgmt-account-id>:role/tfc-mgmt-plan
TFC_AWS_APPLY_ROLE_ARN = arn:aws:iam::<mgmt-account-id>:role/tfc-mgmt-apply
```

> **Why the management-account roles stay manual.** The member-account roles are created in code by a service-managed CloudFormation StackSet (phase-1). Service-managed StackSets **never deploy to the management account**, so these roles stay a phase-0, human-created step. Phase-1 does **not** create a separate "terraform-run" role.

The two management-account ARNs `aws-organization` requires are both phase-0 inputs, carved out of every guardrail deny statement:

| `aws-organization` input | What to pass |
|---|---|
| `terraform_run_role_arn` | The **apply** role above, e.g. `arn:aws:iam::<mgmt-account-id>:role/tfc-mgmt-apply`. Also set it as tfc-admin `aws_management_apply_role_arn` (and the plan role as `aws_management_plan_role_arn`). |
| `break_glass_role_arn` | Either a break-glass role you hand-create now (MFA-required trust, no standing permissions), **or** the ARN the role will have when `aws-security` creates it with `create_break_glass = true`: `arn:aws:iam::<mgmt-account-id>:role/OrganizationBreakGlass` (`break_glass_role_name`). An SCP carve-out may name a role that does not exist yet. |

Every other operator role is created in code (no hand-made role ARN needed):

| Role | Created by | Override |
|---|---|---|
| Member-account `tfc-plan` / `tfc-apply` | `aws-organization` TFC OIDC baseline StackSet | `tfc_workspace_bindings` |
| KMS key administrator (log-archive, forensics, security-tooling CMKs) | Defaults to each key account's own `tfc-apply` role (`key_admin_role_name`) | `key_admin_arn` |
| AWS Config recorder (security tooling, each workload account) | `AWSServiceRoleForConfig` service-linked role, created by `aws-security` / `aws-workload-<env>` | `config_role_arn`; set `create_config_service_linked_role = false` if Config was ever enabled in the account |
| Config organization aggregator | `aws-security` (`aws-config-org-aggregator`, `AWSConfigRoleForOrganizations`) | `aggregator_role_arn` |
| AWS Backup role in every Workloads-OU account | `aws-backup` service-managed StackSet (`aws-backup-org-role`, auto-deploys to new accounts); the org policy names it as `arn:aws:iam::$account:role/aws-backup-org-role` | `backup_role_arn` / `backup_role_name` |
| Backup restore-testing role (backup account) | `aws-backup` (`aws-backup-restore-testing`) | `restore_testing_role_arn` |

With Option A, retire the static key after run #1 and move the workspace to Option B.

### Step 3 — Create the AWS TFC workspaces with `tfc-admin` (pass 1)

Do not hand-create workspaces. [`envs/tfc-admin`](../../envs/tfc-admin/README.md) declares every AWS workspace (`aws-organization`, `aws-security`, `aws-network`, `aws-identity`, `aws-shared-services`, `aws-backup`, one `aws-workload-<env>` per `aws.workload_environments` key) with VCS wiring, working directories, trigger patterns, remote-state sharing and dynamic-credential env vars. Hand-create only the `tfc-admin` workspace itself (working directory `envs/tfc-admin`, a `TFE_TOKEN` sensitive env var).

The cloud flag, the workload environments and their account keys come from the committed `config/landing-zone.yaml` (`scripts/init-landing-zone.sh --clouds aws ...`, or copy [`config/landing-zone.example.yaml`](../../config/landing-zone.example.yaml)):

```yaml
aws:
  enabled: true                 # tfc-admin enable_aws
  workload_environments:
    dev: {account_key: workload_dev}   # aws-workload-dev + its workload_account_key
```

Then apply tfc-admin with only the inputs the file does not hold:

```hcl
aws_management_plan_role_arn  = "arn:aws:iam::<mgmt-account-id>:role/tfc-mgmt-plan"
aws_management_apply_role_arn = "arn:aws:iam::<mgmt-account-id>:role/tfc-mgmt-apply"
vcs_repo                      = { identifier = "<org>/<repo>", oauth_token_id = "ot-..." }
```

Pass 1 sets `TFC_AWS_PROVIDER_AUTH` / `TFC_AWS_PLAN_ROLE_ARN` / `TFC_AWS_APPLY_ROLE_ARN` on `aws-organization` only. `aws-security` and `aws-backup` also run their default provider as the management role, but they get **no** credentials until their member-account alias roles exist (pass 2), because a multi-account workspace with only the default configuration cannot plan.

**Project name must match the role trust.** tfc-admin puts the AWS workspaces in the project `landing-zone-aws` (`project_name_prefix` + `aws`, or `org.tfc.aws_project`; `enable_projects = true`). `aws-organization`'s `tfc_project` now reads the same config key and defaults to `landing-zone-aws` (it used to default to `Default Project`), so the two agree out of the box. Use that project in the Step 2 trust `sub` as well, or every AssumeRoleWithWebIdentity is denied.

**VCS-driven runs get no local tfvars.** Every AWS root reads the committed `config/landing-zone.yaml`: `landing_zone_name` (`org.name`), `owner`, `cost_center`, `aws_region` (`org.regions.aws`), `tfc_organization`, `management_account_id`, `log_archive_bucket_name`, the region lists, the account map and the two role ARNs. An explicit variable still wins. Put any remaining per-workspace inputs in a committed `config/tfc-workspaces.yaml` (copy [`config/tfc-workspaces.example.yaml`](../../config/tfc-workspaces.example.yaml)); tfc-admin sets them as workspace variables (`workspace_variables_file`). Secrets are rejected there: pass them through tfc-admin `workspace_variables` (written write-only). Org-wide values not in the config file belong in `common_workspace_variables`.

**Run #1 state note (the chicken-and-egg).** With Option B the first `aws-organization` run executes remotely in TFC. With Option A (or no TFC credentials yet) set tfc-admin `workspace_execution_modes = { "aws-organization" = "local" }`: the run then executes on your machine with the credentials in your shell while state still lands in the TFC workspace. Switch it back (remove the entry, re-apply tfc-admin) once the Option B roles exist. The `-backend=false` local-state-then-migrate route also works, but is rarely needed now that tfc-admin creates the workspace up front.

Supply the TFC org the same way every root does: `export TF_CLOUD_ORGANIZATION=<your-tfc-org>` before `terraform init` (see `envs/aws/organization/backend.tf`). The `cloud` block accepts no `-backend-config`.

---

## Phase-0.5: org-wide default-VPC-deletion StackSet (out-of-band)

Every AWS account is created with a default VPC in every Region. A single Terraform root **cannot** fan out to every account and every Region to delete them — that is exactly the account-scoped "concern" problem (Convention 9): things that must exist (or not exist) in *every* account are handled per-layer, and brand-new accounts are covered by an **out-of-band CloudFormation StackSet**, not by Terraform in this repo.

**This is a documented manual step, not something Terraform does for you:**

1. In the management (or delegated CloudFormation) account, create a **service-managed StackSet** from the shipped template [`templates/aws/bootstrap/delete-default-vpcs.yaml`](../../templates/aws/bootstrap/delete-default-vpcs.yaml). Target the organization root, or the OUs you care about, with **automatic deployment to new accounts enabled**:

   ```bash
   aws cloudformation create-stack-set --stack-set-name delete-default-vpcs \
     --template-body file://templates/aws/bootstrap/delete-default-vpcs.yaml \
     --permission-model SERVICE_MANAGED --capabilities CAPABILITY_IAM \
     --auto-deployment Enabled=true,RetainStacksOnAccountRemoval=false \
     --parameters ParameterKey=Regions,ParameterValue=eu-west-2
   aws cloudformation create-stack-instances --stack-set-name delete-default-vpcs \
     --deployment-targets OrganizationalUnitIds=<root-id> --regions eu-west-2
   ```

2. The template's custom resource deletes the default VPC, with its default subnets and internet gateway, in each listed Region, or in every enabled Region when the list is empty. A default VPC that still has network interfaces is skipped and reported, never force-deleted.
3. Deploy it **after** the foundational accounts exist (after the phase-1 apply), and leave auto-deployment on so future accounts are cleaned up when they join. List only the allowed Regions: the region-restriction SCP denies the others.

This links to the account-baseline concept: per-account defaults the declarative EC2 policy does **not** cover (default-VPC deletion, EBS-encryption-by-default, account S3 Block Public Access, password policy). The Terraform-managed slice of that baseline is applied per layer via `modules/aws/governance/account-baseline`; the default-VPC deletion specifically stays a StackSet because it cannot be reliably done for every Region from one root.

---

## Who creates the downstream workspaces (decision)

**`envs/tfc-admin` creates every AWS workspace** (Step 3), not a `tfe` provider inside the `aws-organization` root. The AWS org root declares exactly **one** provider (`aws`, management account) and does not self-provision workspaces (see [provider-selection](../architecture/provider-selection.md)).

The **AWS side of the trust is in code.** See the next section.

## Member-account credentials (TFC OIDC baseline)

`aws-organization` (`enable_tfc_oidc_baseline = true`, the default) deploys a **service-managed CloudFormation StackSet** (`tfc-oidc-baseline`, module `modules/aws/iam/tfc-oidc-baseline`). The StackSet targets the OUs of the bound accounts and auto-deploys to accounts that join them. Every bound member account receives:

- an IAM OIDC provider for `https://app.terraform.io` (aud `aws.workload.identity`);
- `tfc-plan` — `ReadOnlyAccess`, trusting only `organization:<tfc_organization>:project:<tfc_project>:workspace:<ws>:run_phase:plan`;
- `tfc-apply` — `AdministratorAccess` by default (`tfc_apply_role_policy_arns`), trusting only `...:workspace:<ws>:run_phase:apply`.

`<ws>` comes from `tfc_workspace_bindings`, a map of account key to workspace names. Workspace names match exactly. The organization and project are always literal. Accounts in a targeted OU without a binding receive only the inert OIDC provider.

Default bindings:

| Account key | Bound workspaces |
|---|---|
| `security_tooling`, `log_archive`, `forensics` | `aws-security` |
| `network` | `aws-network` |
| `shared_services` | `aws-identity`, `aws-shared-services` |
| `backup` | `aws-backup` |
| *(each workload account)* | **not bound by default** — derived from `aws.workload_environments` in `config/landing-zone.yaml` (e.g. `dev: {account_key: workload_dev}` binds `workload_dev` to `aws-workload-dev`), or add e.g. `workload_dev = { workspaces = ["aws-workload-dev"] }` to `tfc_workspace_bindings` |

The role ARNs are published as **`tfc_plan_role_arns`** and **`tfc_apply_role_arns`**. Both are maps keyed by account key:

```bash
terraform -chdir=envs/aws/organization output -json tfc_plan_role_arns
terraform -chdir=envs/aws/organization output -json tfc_apply_role_arns
```

### Per-workspace environment variables

**Single-account roots** authenticate directly as the member role and make no role hop (`assume_role_arn` stays `null`):

| Workspace | `TFC_AWS_PROVIDER_AUTH` | `TFC_AWS_PLAN_ROLE_ARN` | `TFC_AWS_APPLY_ROLE_ARN` |
|---|---|---|---|
| `aws-network` | `true` | `tfc_plan_role_arns["network"]` | `tfc_apply_role_arns["network"]` |
| `aws-identity` | `true` | `tfc_plan_role_arns["shared_services"]` | `tfc_apply_role_arns["shared_services"]` |
| `aws-shared-services` | `true` | `tfc_plan_role_arns["shared_services"]` | `tfc_apply_role_arns["shared_services"]` |
| `aws-workload-<env>` | `true` | `tfc_plan_role_arns["<workload key>"]` | `tfc_apply_role_arns["<workload key>"]` |

tfc-admin sets all of these for you on pass 2 (`aws_organization_outputs_from_tfc = true`); the tables document what it writes. Single-account workspaces map to an account through `tfc_workspace_bindings`, `aws.workload_environments[<env>].account_key` in the config file or tfc-admin `environments[<env>].aws_account_key` (either also sets `workload_account_key` on `aws-workload-<env>`) or `aws_workspace_account_keys`.

**Multi-account roots** (`aws-security`, `aws-backup`) use TFC [multiple dynamic-credential configurations](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials/specifying-multiple-configurations). tfc-admin writes the default configuration from `aws_management_plan_role_arn` / `aws_management_apply_role_arn` and one configuration per alias from the `aws-organization` outputs (override with `aws_alias_role_arns`). It never maps these workspaces to a member account's role as their default, and it withholds all of their AWS credentials until every alias has roles:

- The **default** configuration is the phase-0 management-account plan/apply role from Step 2.
- Each member-account provider alias authenticates **directly** as that account's `tfc-plan` / `tfc-apply` role. There is no role chaining from the management account. TFC injects `var.tfc_aws_dynamic_credentials` and the provider aliases read their `shared_config_file` from it.

```text
# default — management account (org CloudTrail, delegated admin, org backup policy)
TFC_AWS_PROVIDER_AUTH  = true
TFC_AWS_PLAN_ROLE_ARN  = arn:aws:iam::<mgmt-account-id>:role/tfc-mgmt-plan
TFC_AWS_APPLY_ROLE_ARN = arn:aws:iam::<mgmt-account-id>:role/tfc-mgmt-apply

# one block per alias: aws-security -> security_tooling, log_archive, forensics; aws-backup -> backup
TFC_AWS_PROVIDER_AUTH_<alias>  = true
TFC_AWS_PLAN_ROLE_ARN_<alias>  = tfc_plan_role_arns["<alias>"]
TFC_AWS_APPLY_ROLE_ARN_<alias> = tfc_apply_role_arns["<alias>"]
```

> **Legacy / local fallback (not recommended).** To run from management-account credentials, as before the baseline existed:
> - **Single-account roots:** set the Terraform variable `assume_role_arn = account_role_arns["<key>"]` (OrganizationAccountAccessRole).
> - **`aws-security` / `aws-backup`:** leave `tfc_aws_dynamic_credentials` unset; their aliases then assume `account_role_arns[...]`.
>
> This brings back management-rooted credentials for member-account work. Use it only for break-glass or local debugging.

## Full first-time stand-up order

Follow this order top to bottom. **Manual gates** are inline and must be completed before the next Terraform step will succeed. Remember: ordering is enforced by apply order and remote-state reads, not by any cross-root `depends_on`.

1. **Phase-0** — management account, bootstrap identity, `aws-organization` workspace (Steps 1–3 above).

2. **Apply `aws-organization`.** Its inputs come from the committed `config/landing-zone.yaml`: `org.name`, real unique root emails for every account in `aws.accounts` / `aws.workload_accounts`, `aws.terraform_run_role_arn` and `aws.break_glass_role_arn` (see Step 2), and `aws.log_archive_bucket_name`. The workload bindings are derived from `aws.workload_environments`. Explicit variables (`config/tfc-workspaces.yaml`, or `terraform.tfvars` for a local run) override them. Then apply:

   ```bash
   terraform -chdir=envs/aws/organization apply
   ```

   `tfc_organization` comes from `org.tfc.organization`. `tfc_project` defaults to the tfc-admin AWS project (`landing-zone-aws`, or `org.tfc.aws_project`), which must match the workspace project literally. The apply creates the org, the OU tree, the foundational accounts, the guardrails and the **TFC OIDC baseline StackSet**. It publishes `account_ids`, `account_role_arns`, `tfc_plan_role_arns` and `tfc_apply_role_arns`.

   > **StackSets trusted access.** The organization module enables `member.org.stacksets.cloudformation.amazonaws.com` trusted access. If the StackSet create fails with an organizations-access error, run `aws cloudformation activate-organizations-access` once in the management account and re-apply. It is idempotent, and it is the AWS-recommended way to enable StackSets trusted access.

3. **MANUAL GATE — IAM Identity Center.** In the **management account**, enable IAM Identity Center (console action — cannot be created by Terraform here), then **delegate administration to the Shared Services account**. The `aws-identity` root manages permission sets and assignments *after* this delegation exists; it cannot enable Identity Center for you.

4. **tfc-admin pass 2 — downstream credentials.** The workspaces already exist (Step 3). Set `aws_organization_outputs_from_tfc = true` on tfc-admin and re-apply it. It reads `tfc_plan_role_arns` / `tfc_apply_role_arns` / `tfc_workspace_bindings` from `aws-organization` and writes `TFC_AWS_PROVIDER_AUTH` / `TFC_AWS_PLAN_ROLE_ARN` / `TFC_AWS_APPLY_ROLE_ARN` on every single-account workspace, plus the management default and the `TFC_AWS_*_<alias>` sets on `aws-security` / `aws-backup` (see [Member-account credentials](#member-account-credentials-tfc-oidc-baseline)). The role trust is already in place from step 2, provided the workspace name is in `tfc_workspace_bindings` and `tfc_project` matches the workspace project.

5. **Phase-0.5 — default-VPC-deletion StackSet.** Deploy the org-wide StackSet now that the accounts exist (see phase-0.5 section). Leave auto-deployment on.

6. **Apply `aws-security`.** Security tooling, log archive, org CloudTrail, GuardDuty, Security Hub, Config aggregator — the second half of the minimum governed baseline.

7. **Apply `aws-network`.** Shared networking (TGW, resolver, shared VPC constructs) in the network account.

8. **Apply `aws-identity`.** Permission sets and account assignments, now that Identity Center is delegated (gate in step 3).

9. **Apply `aws-shared-services`** *(optional / gated).* Shared platform services; apply only if you need them.

10. **Apply `aws-backup`.** Centralized AWS Backup vaults and plans.

11. **Apply `aws-workload-<env>`** *(per environment).* Select the env with `TF_WORKSPACE=aws-workload-<env>`. Each apply stands up that env's spoke VPC, workload roles, and per-account baseline. Repeat per environment.

12. **Apply `saas`** *(optional).* Supabase and/or Vercel only, gated by `enable_supabase` / `enable_vercel`. Configures no AWS provider.

> Each downstream root **reads the `aws-organization` remote state** for `account_ids` (its `allowed_account_ids` guard), `account_role_arns` (legacy fallback only) and other contract outputs. If you apply one before `aws-organization`, it fails at plan time. The minimum governed footprint is just `aws-organization` + `aws-security`; everything else is additive (see [provider-selection](../architecture/provider-selection.md#minimum-aws-footprint)).

---

## Teardown

Teardown is the **reverse** of the stand-up order (destroy workloads first, `aws-organization` last), and it carries a hard caveat: the Log Archive bucket uses **S3 Object Lock in COMPLIANCE mode**, which cannot be shortened or bypassed even by the root user — objects are immutable until their retention expires, so the bucket (and often the whole `log_archive` account) cannot be destroyed on demand.

The full reverse-order destroy procedure and the Object-Lock caveat are covered in [`aws-teardown.md`](aws-teardown.md). Do not attempt a blind `terraform destroy` across roots before reading it.

---

## See also

- [Quick Start](../guides/QUICK_START.md) — the GCP-side bootstrap this mirrors.
- [Provider Selection](../architecture/provider-selection.md) — why one cloud = one root = one workspace, and the combination matrix.
- [Adding a Cloud](../architecture/adding-a-cloud.md) — the cross-root contract (stable output keys, aliased foundational providers, credential-free remote state).
