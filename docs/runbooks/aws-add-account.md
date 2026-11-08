# Runbook: Add an AWS Account / Environment

**When to use:** You need to add a new member account to the organization — either a new foundational account or (far more commonly) a new per-env **workload** account. This is the steady-state equivalent of the first-time stand-up in [`aws-bootstrap.md`](aws-bootstrap.md): the org already exists, so you are adding one row and wiring one new workspace.

**Time:** 20–40 minutes of hands-on Terraform + TFC work, plus AWS account-creation wait (a few minutes) and any manual OU/email confirmation.
**Risk:** Medium. Account creation is org-mutating and hard to reverse (see the `close_on_deletion` caveats in [`aws-teardown.md`](aws-teardown.md)). The apply happens in the `aws-organization` root, whose blast radius is the whole org.
**Prerequisites:** The landing zone is already stood up per [`aws-bootstrap.md`](aws-bootstrap.md). You can commit to `config/landing-zone.yaml`, and you have a unique root email for the new account, and permission to create a TFC workspace and set its variables.

---

> This runbook assumes the [cross-root contract](../architecture/adding-a-cloud.md). The `aws-organization` root **produces** `account_ids`, `tfc_plan_role_arns` and `tfc_apply_role_arns`. A downstream workspace authenticates **directly into its member account** with TFC dynamic credentials for that account's `tfc-plan` / `tfc-apply` role. The [TFC OIDC baseline](aws-bootstrap.md#member-account-credentials-tfc-oidc-baseline) StackSet creates those roles. Adding an account takes three steps: bind its workspace in the org root, apply, then point the new workspace at the published roles.

---

## Step 1 — Add the account to the org map

Edit the committed `config/landing-zone.yaml`. For a **workload** account, add a row to `aws.workload_accounts` **and** an `aws.workload_environments` entry naming it. For a foundational account, add to `aws.accounts`.

```yaml
aws:
  workload_accounts:
    # ...existing...
    payments_prod: {email: aws+payments-prod@example.com, ou: Workloads/Prod}   # child OUs are keyed by path
  workload_environments:
    # ...existing...
    payments-prod: {account_key: payments_prod}   # env key: hyphens, not underscores
```

The `workload_environments` key is the environment name: `aws-workload` accepts only lowercase letters, digits and hyphens there (`^[a-z][a-z0-9-]{0,30}$`), so use `payments-prod`. The account key (`payments_prod`) may keep its underscore.

That single edit drives three roots. `aws-organization` vends the account and derives its OIDC trust binding (`payments_prod` → `aws-workload-payments-prod`). tfc-admin creates the `aws-workload-payments-prod` workspace with `workload_account_key = "payments_prod"`. `aws-workload` reads the same mapping. Without a binding, the account gets only the OIDC provider and no roles.

If `aws-organization` sets `workload_accounts` or `tfc_workspace_bindings` **explicitly** (tfvars or a TFC variable), the explicit value wins over the file. Add the entry there instead, keeping the foundational defaults:

```hcl
tfc_workspace_bindings = {
  # ...existing (the variable default lists the foundational bindings — keep them)...
  payments_prod = { workspaces = ["aws-workload-payments-prod"] }
}
```

Rules:

- **Root email must be globally unique** across all AWS accounts, ever. A reused email (including one freed by a closed account) will fail. Use a `+` alias on a monitored inbox.
- The **map key is the account name** — it becomes the key in the `account_ids` / `account_role_arns` outputs and the suffix of the workspace (`aws-workload-<key>`). Keep it stable; renaming it destroys and recreates the account.
- `ou` places the account. Workload accounts go under the `Prod` / `NonProd` child OUs, written as their full path (`Workloads/Prod`, `Workloads/NonProd`), because `aws-organization` keys child OUs by path; foundational accounts under `Security` / `Infrastructure` (see [`aws-landing-zone.md`](../architecture/aws-landing-zone.md#account--ou-model)).

---

## Step 2 — Apply `aws-organization`

This is the only Terraform step that touches the org. Apply via Terraform Cloud (never a local apply against this root):

```bash
terraform -chdir=envs/aws/organization plan   # local read-only check
# then apply via the aws-organization TFC workspace
```

The apply creates the account and places it in the OU. It also updates the `tfc-oidc-baseline` StackSet, so the new account gets the OIDC provider and its `tfc-plan` / `tfc-apply` roles. Each role trusts only `organization:<tfc_organization>:project:<tfc_project>:workspace:aws-workload-payments-prod:run_phase:<plan|apply>`.

> If the account's OU was not already a StackSet target, the apply adds a stack instance for that OU. Otherwise auto-deployment creates the stack when the account joins the OU. In both cases, check that the stack instance is `CURRENT` before Step 4: CloudFormation console, StackSets, `tfc-oidc-baseline`, Stack instances.

Confirm that the new role ARNs are published:

```bash
terraform -chdir=envs/aws/organization output -json tfc_plan_role_arns   # expect a "payments_prod" key
terraform -chdir=envs/aws/organization output -json tfc_apply_role_arns
```

---

## Step 3 — Create the TFC workspace and wire its run role (tfc-admin)

`envs/tfc-admin` creates and wires the workspace (see the decision section in [`aws-bootstrap.md`](aws-bootstrap.md#who-creates-the-downstream-workspaces-decision)). It already knows the environment from `aws.workload_environments` (Step 1). An explicit tfc-admin `environments` variable overrides the config file; if you set one, add `payments-prod = { aws_account_key = "payments_prod" }` to it. Make sure `aws_organization_outputs_from_tfc = true`.

Re-apply tfc-admin. It creates `aws-workload-payments-prod` (VCS, working directory `envs/aws/workload`, triggers, remote-state access to `aws-organization` / `aws-network` / `aws-security`) and sets:

| Variable | Kind | Value |
|---|---|---|
| `environment` | terraform | `payments-prod` (from the workspace name) |
| `workload_account_key` | terraform | `payments_prod` (from `aws.workload_environments[*].account_key`) |
| `TFC_AWS_PROVIDER_AUTH` | env | `true` |
| `TFC_AWS_PLAN_ROLE_ARN` | env | `tfc_plan_role_arns["payments_prod"]` |
| `TFC_AWS_APPLY_ROLE_ARN` | env | `tfc_apply_role_arns["payments_prod"]` |

Shared inputs (`landing_zone_name`, `tfc_organization`, region, tags) come from `config/landing-zone.yaml`. Put the workspace's other Terraform inputs (`kms_key_arn`, …) in the committed `config/tfc-workspaces.yaml` under `aws-workload-payments-prod`, because VCS-driven runs get no local tfvars. Leave `assume_role_arn` unset (`null`), so the provider uses the dynamic credentials directly with no role hop. Speculative PR plans then run as the read-only `tfc-plan` role.

**Trust:** nothing to do by hand. The roles already trust exactly this workspace name, because of the Step 1 binding. The workspace name must match the binding character for character, and the binding's project (`tfc_project`, default `landing-zone-aws`, matching tfc-admin) must match the workspace's project.

For a **foundational** account, use the corresponding key (`security_tooling`, `network`, `shared_services`, `backup`, …) and the matching layer root/workspace instead of `aws-workload-*`. The multi-account `aws-security` / `aws-backup` workspaces use per-alias variables (`TFC_AWS_PROVIDER_AUTH_<alias>`, `TFC_AWS_PLAN_ROLE_ARN_<alias>`, `TFC_AWS_APPLY_ROLE_ARN_<alias>`) for each member account they touch; tfc-admin derives them from the same outputs. See [aws-bootstrap](aws-bootstrap.md#per-workspace-environment-variables).

---

## Step 4 — Apply the layer

Apply the relevant layer root for the new account. For a workload account:

```bash
export TF_WORKSPACE=aws-workload-payments-prod
terraform -chdir=envs/aws/workload plan   # read-only local check; apply via TFC
```

> **Deployment ordering — org first, always.** The workload entry must be added
> to `aws.workload_accounts` (the `aws-organization` root's `workload_accounts`) **and**
> `aws-organization` must be applied (Steps 1–2) *before* you plan or apply the
> new `aws-workload-<env>` workspace. Until the org root has published the
> key and the StackSet has created the account's `tfc-plan` role, the workspace
> has no role to authenticate as. TFC fails the run at the credential step
> (`AssumeRoleWithWebIdentity` access denied) before it can produce a plan. This is the same cross-root contract described in
> the header note: publish from the org root first, then consume downstream.

This stands up the env's spoke VPC, its TGW attachment, workload roles, and the per-account baseline. The attachment is created in the workload account and waits for the network account (state `pendingAcceptance`); **the spoke has no routing until the next step.**

**Wire the spoke into the hub.** Only the TGW owner can accept the attachment and associate it with a route table. Copy the workspace's `tgw_attachment_id` output into `config/landing-zone.yaml`:

```yaml
aws:
  network:
    spoke_attachments:
      payments-prod: {attachment_id: tgw-attach-0123456789abcdef0, segment: prod}   # segment: prod | nonprod
```

Then apply `aws-network`. It accepts the attachment, associates it with the `prod` / `nonprod` route table (whose `0.0.0.0/0` goes to inspection) and propagates the spoke CIDR into the inspection table, so egress replies and on-premises traffic reach it (see [network topology](../architecture/aws-landing-zone.md#network-topology)). Set `accept: false` for an attachment that is already accepted.

> **New-account defaults not covered by Terraform.** A brand-new account still has a default VPC per Region and needs EBS-encryption-by-default, S3 Block Public Access, and a password policy. The default-VPC deletion is handled by the org-wide **auto-deploying StackSet** from [`aws-bootstrap.md`](aws-bootstrap.md#phase-05-org-wide-default-vpc-deletion-stackset-out-of-band); the rest is applied per layer via `modules/aws/governance/account-baseline`. Confirm the StackSet auto-deployed to the new account.

---

## Step 5 — Verify

- The account appears in the correct OU (AWS Organizations console).
- The `tfc-oidc-baseline` stack instance for the account is `CURRENT`, and the workspace's plan ran as `tfc-plan` (check the run's credential log line).
- The layer apply succeeded and the workspace holds state.
- The spoke's TGW attachment is `available` and associated with the `prod` / `nonprod` route table (`aws ec2 get-transit-gateway-attachment-propagations` / `describe-transit-gateway-attachments` in the network account).
- GuardDuty / Config / Security Hub auto-enrolled the new account (delegated admin in Security Tooling — see [security services](../architecture/aws-landing-zone.md#security-services)).
- The default VPC was removed by the StackSet.

---

## See also

- [AWS Bootstrap](aws-bootstrap.md) — first-time stand-up and workspace-creation mechanics.
- [AWS Landing Zone](../architecture/aws-landing-zone.md) — account/OU model and layer map.
- [AWS Teardown](aws-teardown.md) — `close_on_deletion` caveats before you remove an account.
