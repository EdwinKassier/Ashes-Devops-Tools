# Runbook: AWS Break-Glass Emergency Access

**When to use:** The normal access path into an AWS member account is unavailable during an incident — the TFC run role is broken, IAM Identity Center is down, or a guardrail (SCP/RCP) is unexpectedly blocking a legitimate emergency action — and you need elevated access to investigate or remediate. This is the AWS counterpart to the GCP [break-glass runbook](break-glass.md).

**Time:** 5–15 minutes to activate; longer if you are recovering from an SCP lockout.
**Risk:** High. Break-glass bypasses the org guardrails by design. Every action must be logged (org CloudTrail → Log Archive) and the role re-disabled immediately after the incident.
**Prerequisites:** You know the account-qualified break-glass role ARN (`break_glass_role_arn`), you hold the MFA device registered for it, and — for the SCP-lockout path — you have access to the **management account** (root or an admin).

---

> **This procedure bypasses org guardrails. Use it only during a genuine incident where normal access is unavailable.** All break-glass activity is captured by the org CloudTrail in the Log Archive account. Post-incident review is mandatory.

---

## How the break-glass role is wired

Understand the design before you rely on it:

- **Disabled by default.** The break-glass role carries a **deny-all standing policy**. In normal operation it can do nothing — it is inert until activated (Step 2).
- **MFA-required.** Its trust/permission conditions require MFA, so a leaked credential alone cannot use it.
- **Carved out of the guardrails.** Its **account-qualified exact ARN** (`arn:aws:iam::<account>:role/...`) is listed as an exception in the SCP/RCP deny statements rendered by `modules/aws/organization-policy` (`break_glass_role_arn`). That carve-out is why, once activated, it can act where the deny statements would otherwise block everyone. Because the exception is by exact ARN, no other principal inherits the exemption.

---

## Step 1 — Confirm break-glass is actually required

| Scenario | Break-glass? |
|---|---|
| TFC run role / dynamic credentials broken | Yes |
| IAM Identity Center down, no other admin path | Yes |
| An SCP is blocking a legitimate emergency change | Yes (or use the management-account recovery below) |
| Normal PR/CI is just slow | No |
| Routine log review | No — use read-only Identity Center access |

Log the incident, the approver, and a time box before proceeding.

---

## Step 2 — Activate the role

Break-glass is off until you deliberately turn it on. Activation means **replacing the deny-all standing policy with the intended emergency permissions** (and confirming MFA is enforced):

1. In the target account, attach the pre-defined emergency permission policy to the break-glass role (removing/overriding the deny-all standing policy). This is a deliberate, logged mutation.
2. Assume the role **with MFA**:

   ```bash
   aws sts assume-role \
     --role-arn arn:aws:iam::<account-id>:role/<break-glass-role> \
     --role-session-name break-glass-$(date +%Y%m%dT%H%M) \
     --serial-number arn:aws:iam::<account-id>:mfa/<your-mfa> \
     --token-code <mfa-code>
   ```

3. Export the returned short-lived credentials and perform the minimum necessary remediation.

Because the role's exact ARN is carved out of the SCP/RCP deny statements, actions that guardrails would normally deny are permitted **for this ARN only**.

---

## Step 3 — Recover from an "SCP locked everyone out" situation

If an SCP change has locked out **all** member-account principals (including the break-glass role, or you cannot activate it), recover from the **management account**:

> **The management account is never restricted by SCPs.** AWS does not apply Service Control Policies to the organization's own management (payer) account. It can therefore always detach or edit policies even when every member account is fully denied.

1. Sign in to the **management account** (via IAM Identity Center admin, an IAM admin, or root as a last resort).
2. In AWS Organizations, **detach the offending SCP** from the affected OU/account (or edit its deny statement):

   ```bash
   aws organizations detach-policy \
     --policy-id <p-xxxxxxxx> \
     --target-id <ou-or-account-id>
   ```

3. Once access is restored, fix the policy in Terraform (`modules/aws/organization-policy`) and re-apply through the `aws-organization` workspace — do not leave the guardrail detached.

> **The management-account root is NOT SCP-protected and must be secured out-of-band.** Because no SCP can constrain it, its compromise is catastrophic. Enforce: a **hardware MFA** device on root, **no root access keys**, root email on a monitored, tightly controlled inbox, and root sign-in alarms. This is the ultimate break-glass path — treat it as such.

---

## Step 4 — Deactivate and review (MANDATORY)

**Before closing the incident:**

1. **Re-disable the break-glass role** — restore the deny-all standing policy so the role is inert again.
2. **Re-attach any detached SCP** (Step 3) and confirm the guardrail is back via a fresh `aws-organization` apply.
3. **Pull the audit trail** from the org CloudTrail in the Log Archive account for the break-glass session window; verify only authorized actions were taken.
4. File the post-incident review within 24 hours. If unauthorized actions are found, escalate as a security incident (see [`aws-incident-response.md`](aws-incident-response.md)).

---

## See also

- [AWS Landing Zone](../architecture/aws-landing-zone.md#root-access-management--break-glass) — guardrails and root-access management.
- [AWS Incident Response](aws-incident-response.md) — quarantine and forensics flow.
- [GCP Break-Glass](break-glass.md) — the GCP-side procedure this mirrors.
