# Runbook: Add an AWS Account / Environment

**When to use:** You need to add a new member account to the organization — either a new foundational account or (far more commonly) a new per-env **workload** account. This is the steady-state equivalent of the first-time stand-up in [`aws-bootstrap.md`](aws-bootstrap.md): the org already exists, so you are adding one row and wiring one new workspace.

**Time:** 20–40 minutes of hands-on Terraform + TFC work, plus AWS account-creation wait (a few minutes) and any manual OU/email confirmation.
**Risk:** Medium. Account creation is org-mutating and hard to reverse (see the `close_on_deletion` caveats in [`aws-teardown.md`](aws-teardown.md)). The apply happens in the `aws-organization` root, whose blast radius is the whole org.
**Prerequisites:** The landing zone is already stood up per [`aws-bootstrap.md`](aws-bootstrap.md). You have write access to `envs/aws-organization/terraform.tfvars`, a unique root email for the new account, and permission to create a TFC workspace and set its variables.

---

> This runbook assumes the [cross-root contract](../architecture/adding-a-cloud.md): the `aws-organization` root **produces** `account_ids` and `account_role_arns`; downstream roots **consume** a role ARN from `account_role_arns` to authenticate. Adding an account is: publish a new role ARN from the org root, then point a new workspace at it.

---

## Step 1 — Add the account to the org map

Edit `envs/aws-organization/terraform.tfvars`. For a **workload** account, add a row to `workload_accounts`; for a foundational account, add to `accounts`.

```hcl
# Workload account — placed under Workloads/Prod or Workloads/NonProd
workload_accounts = {
  # ...existing...
  payments_prod = { email = "aws+payments-prod@example.com", ou = "Prod" }
}
```

Rules:

- **Root email must be globally unique** across all AWS accounts, ever. A reused email (including one freed by a closed account) will fail. Use a `+` alias on a monitored inbox.
- The **map key is the account name** — it becomes the key in the `account_ids` / `account_role_arns` outputs and the suffix of the workspace (`aws-workload-<key>`). Keep it stable; renaming it destroys and recreates the account.
- `ou` places the account. Workload accounts go under the `Prod` / `NonProd` child OUs; foundational accounts under `Security` / `Infrastructure` (see [`aws-landing-zone.md`](../architecture/aws-landing-zone.md#account--ou-model)).

---

## Step 2 — Apply `aws-organization`

This is the only Terraform step that touches the org. Apply via Terraform Cloud (never a local apply against this root):

```bash
terraform -chdir=envs/aws-organization plan   # local read-only check
# then apply via the aws-organization TFC workspace
```

The apply creates the account, places it in the OU, and — for workload accounts — the per-account cross-account access role, which is exported in the updated `account_role_arns` map.

Confirm the new role ARN is published:

```bash
terraform -chdir=envs/aws-organization output -json account_role_arns
# expect a "payments_prod" key
```

---

## Step 3 — Create the TFC workspace and wire its run role

Create the downstream workspace out-of-band (the org root does **not** self-provision workspaces — see the decision section in [`aws-bootstrap.md`](aws-bootstrap.md#who-creates-the-downstream-workspaces-decision)):

1. **Workspace name:** `aws-workload-<key>` (e.g. `aws-workload-payments_prod`). For a per-env root this matches the `aws-workload-` prefix; the env is selected with `TF_WORKSPACE`.
2. **VCS + working directory:** connect to this repo, working directory `envs/aws-workload`.
3. **Run role:** set the workspace's `TFC_AWS_RUN_ROLE_ARN` to the matching value from `account_role_arns[...]`:

   ```text
   TFC_AWS_PROVIDER_AUTH = true
   TFC_AWS_RUN_ROLE_ARN  = <account_role_arns["payments_prod"] from Step 2>
   ```

4. Ensure that member-account role **trusts** this workspace's TFC identity — same wiring you do for any downstream workspace.

For a **foundational** account, use the corresponding key (`security_tooling`, `network`, `shared_services`, `backup`, …) and the matching layer root/workspace instead of `aws-workload-*`.

---

## Step 4 — Apply the layer

Apply the relevant layer root for the new account. For a workload account:

```bash
export TF_WORKSPACE=aws-workload-payments_prod
terraform -chdir=envs/aws-workload plan   # read-only local check; apply via TFC
```

This stands up the env's spoke VPC (attached to the TGW with the correct Prod/NonProd route table — see [network topology](../architecture/aws-landing-zone.md#network-topology)), workload roles, and the per-account baseline.

> **New-account defaults not covered by Terraform.** A brand-new account still has a default VPC per Region and needs EBS-encryption-by-default, S3 Block Public Access, and a password policy. The default-VPC deletion is handled by the org-wide **auto-deploying StackSet** from [`aws-bootstrap.md`](aws-bootstrap.md#phase-05-org-wide-default-vpc-deletion-stackset-out-of-band); the rest is applied per layer via `modules/aws/account-baseline`. Confirm the StackSet auto-deployed to the new account.

---

## Step 5 — Verify

- The account appears in the correct OU (AWS Organizations console).
- The layer apply succeeded and the workspace holds state.
- GuardDuty / Config / Security Hub auto-enrolled the new account (delegated admin in Security Tooling — see [security services](../architecture/aws-landing-zone.md#security-services)).
- The default VPC was removed by the StackSet.

---

## See also

- [AWS Bootstrap](aws-bootstrap.md) — first-time stand-up and workspace-creation mechanics.
- [AWS Landing Zone](../architecture/aws-landing-zone.md) — account/OU model and layer map.
- [AWS Teardown](aws-teardown.md) — `close_on_deletion` caveats before you remove an account.
