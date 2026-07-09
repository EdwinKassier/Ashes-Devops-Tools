# Runbook: AWS Landing Zone Teardown

**When to use:** You are decommissioning some or all of the AWS landing zone — a single workload env, or the whole org. This is the reverse of the stand-up in [`aws-bootstrap.md`](aws-bootstrap.md), and it carries hard, **intended** immutability caveats that mean a full clean `terraform destroy` is often impossible within the retention windows.

**Time:** Minutes-to-hours per layer for the destroyable parts; the immutable parts (WORM log bucket, Vault-Lock backups) cannot be destroyed until their retention expires — potentially **years**.
**Risk:** Very high and largely irreversible. Account closure is rate-limited and slow to reverse; compliance-mode locks cannot be overridden even by root. Read this entire runbook before running any `destroy`.
**Prerequisites:** You understand the [layer map](../architecture/aws-landing-zone.md#layer-map--which-root-deploys-what) and have destroy-capable access to each workspace. Confirm no other environment depends on shared resources you are about to remove.

---

> **Do not run a blind `terraform destroy` across roots.** There is no cross-root `depends_on`; ordering is your responsibility. Destroying an upstream layer while a downstream layer still holds attachments to it will leave orphaned resources and failed destroys.

---

## Reverse-order destroy

Destroy in the **exact reverse** of the stand-up order. Each layer must be fully destroyed before the one above it:

```text
7. aws-workload-<env>     (per env — destroy every workload workspace first)
6. aws-backup             (see Vault Lock caveat — may not destroy)
5. aws-shared-services
4. aws-identity           (remove Identity Center assignments/permission sets)
3. aws-network            (detach spokes before destroying the TGW)
2. aws-security           (see Object Lock caveat — will NOT destroy)
1. aws-organization       (last — accounts + org; see close_on_deletion caveat)
```

The `saas` root is independent of the AWS chain — destroy it whenever, it holds no AWS resources.

For each layer, apply via its TFC workspace:

```bash
export TF_WORKSPACE=aws-workload-<env>   # for per-env roots
terraform -chdir=envs/aws-workload destroy   # run through TFC, not locally
```

---

## Caveat 1 — Log Archive bucket: Object Lock COMPLIANCE (WORM, even against root)

The Log Archive bucket (`modules/aws/log-archive-bucket`) defaults to **S3 Object Lock in COMPLIANCE mode** with a default retention of `retention_days`.

- In COMPLIANCE mode, **no one — including the AWS account root and the org management account — can delete or shorten the retention of a locked object** until its retention period expires. This is WORM by regulatory design.
- Therefore the bucket **cannot be emptied or destroyed** while any object is still within its retention window, and the destroy of `aws-security` (and often the whole `log_archive` account) **will fail** until then.

**This is intended, not a bug.** It is the property that makes the audit log tamper-proof. Do not "fix" it by switching to GOVERNANCE mode after the fact — you can't retroactively unlock COMPLIANCE-locked objects. To decommission, you must **wait out the retention window**; the account/bucket stays until the last locked object expires.

---

## Caveat 2 — Backup Vault Lock: Compliance mode is also immutable

The Backup vaults (`modules/aws/backup-vault`) use **AWS Backup Vault Lock in Compliance mode** (a non-null `changeable_for_days` cooling-off window enables it).

- During the `changeable_for_days` cooling-off window the lock can still be removed. **After the window elapses the lock is immutable** — recovery points cannot be deleted and the vault cannot be emptied or destroyed until each recovery point's retention expires, again **not even by root**.
- So `aws-backup` will not fully destroy while locked recovery points exist. Same posture as the log bucket: wait out retention.

---

## Caveat 3 — Account closure (`close_on_deletion`)

The `account` module (`modules/aws/account`) exposes `close_on_deletion` (default `false`). Understand both settings:

- **`close_on_deletion = false` (default):** destroying the account resource only **removes it from the organization**; the account itself survives as a standalone account. Nothing is closed.
- **`close_on_deletion = true`:** destroying the account resource **closes** the AWS account. Beware:
  - **Rate limits.** AWS limits how many accounts you can close in a rolling period (a small percentage of the org's account count per month, minimum a handful). Bulk teardown of many accounts will throttle.
  - **~90-day SUSPENDED window.** A closed account enters a **SUSPENDED** state for roughly 90 days during which it can be reopened, and is only then permanently deleted. It still counts against org limits during that window.
  - **Email reuse.** The root email of a closed account **cannot be reused** for a new account (immediately, and generally not at all). Plan email aliases accordingly (see [`aws-add-account.md`](aws-add-account.md)).

Because closure is slow and hard to reverse, prefer removing accounts from the org (keep `close_on_deletion = false`) and closing them manually and deliberately later.

---

## Order-of-operations gotchas

- **Network:** detach all spoke VPC attachments from the Transit Gateway before destroying `aws-network`, or the TGW destroy fails.
- **Identity:** remove IAM Identity Center account assignments and permission sets (`aws-identity`) before touching the accounts they reference.
- **Delegated admin:** the security services (GuardDuty/Config/Security Hub) are delegated to Security Tooling; de-register delegation as part of `aws-security` destroy, and expect member auto-enrollment to need cleanup.
- **Org last:** `aws-organization` can only be destroyed once every member account has been removed/closed and no OU still contains accounts.

---

## See also

- [AWS Bootstrap](aws-bootstrap.md) — the stand-up order this reverses.
- [AWS Landing Zone](../architecture/aws-landing-zone.md) — layer map and immutability rationale.
- [AWS Add Account](aws-add-account.md) — `close_on_deletion` and email-reuse context.
