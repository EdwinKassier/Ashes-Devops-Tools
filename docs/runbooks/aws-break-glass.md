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

- **Created by the phase-0 stack (default).** [`templates/aws/bootstrap/phase0-management.yaml`](../../templates/aws/bootstrap/phase0-management.yaml) creates `OrganizationBreakGlass` in the **management account**. Pass its ARN in as `aws.break_glass_role_arn` / `break_glass_role_arn`, and keep `create_break_glass = false` on `aws-security`. The least-privilege `aws-security` management role is deliberately **denied** any access to the break-glass role, which every member break-glass role trusts. A pipeline that could edit it could promote itself to break-glass.
- **In-repo alternative (`create_break_glass = true`).** This works only when `aws-security` applies as the phase-0 management role. The dedicated `tfc-mgmt-aws-security-*` role has no IAM write permissions, so the apply fails with AccessDenied.
- **Disabled by default.** The break-glass role carries a **deny-all standing policy**. In normal operation it can do nothing — it is inert until activated (Step 2).
- **MFA-required.** Its trust policy requires MFA and bounds the MFA session age, so a leaked credential alone cannot use it. Trust is scoped to `break_glass_trusted_principals` (a small set of senior responders).
- **Monitored.** Every assumption of the role is alarmed by `modules/aws/security/security-notifications`: an always-on EventBridge rule, plus a CloudWatch metric alarm when the org CloudTrail log group is set. The alarm watches the **effective** ARN (the stage-created role when `create_break_glass` is true), so management and monitoring never drift apart.
- **Carved out of the guardrails.** Its **account-qualified exact ARN** (`arn:aws:iam::<account>:role/...`) is listed as an exception in the SCP/RCP deny statements rendered by `modules/aws/governance/organization-policy` (`break_glass_role_arn`). That carve-out is why, once activated, it can act where the deny statements would otherwise block everyone. Because the exception is by exact ARN, no other principal inherits the exemption.

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

Break-glass is off until you deliberately turn it on. Activation means **replacing the deny-all standing policy with AdministratorAccess** (and confirming MFA is enforced). There are two paths:

- **Phase-0 stack role (default):** as a management-account administrator, or root in a true emergency, update the stack with `BreakGlassActive=true`. That removes the `standby-deny-all` inline policy and leaves `AdministratorAccess` effective. This works even when Terraform, TFC and CI are all down:

  ```bash
  aws cloudformation update-stack --stack-name ashes-phase0 --use-previous-template \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameters ParameterKey=BreakGlassActive,ParameterValue=true \
      ParameterKey=TfcOrganization,UsePreviousValue=true ParameterKey=TfcProject,UsePreviousValue=true \
      ParameterKey=TfcHostname,UsePreviousValue=true ParameterKey=TrustSecurityAndBackup,UsePreviousValue=true \
      ParameterKey=BreakGlassTrustedPrincipalArn,UsePreviousValue=true ParameterKey=BreakGlassMfaMaxAgeSeconds,UsePreviousValue=true
  ```

  If CloudFormation itself is unavailable, delete the `standby-deny-all` inline policy by hand and record it. Step 4 restores it.
- **In-repo role (`create_break_glass = true`, applied as the phase-0 role):** set `break_glass_active = true` on the `aws-security` stage and apply as the phase-0 role. Flip it back in Step 4. The dedicated aws-security pipeline role cannot do this.

Then:

1. Confirm the standing deny-all policy has been replaced by the emergency permissions.
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

3. Once access is restored, fix the policy in Terraform (`modules/aws/governance/organization-policy`) and re-apply through the `aws-organization` workspace — do not leave the guardrail detached.

> **The management-account root is NOT SCP-protected and must be secured out-of-band.** Because no SCP can constrain it, its compromise is catastrophic. Enforce: a **hardware MFA** device on root, **no root access keys**, root email on a monitored, tightly controlled inbox, and root sign-in alarms. This is the ultimate break-glass path — treat it as such.

---

## Step 4 — Deactivate and review (MANDATORY)

**Before closing the incident:**

1. **Re-disable the break-glass role**, so the role is inert again:
   - **Phase-0 stack role:** update the stack with `BreakGlassActive=false`. If you deleted the inline policy by hand, the same update restores it.
   - **In-repo role:** set `break_glass_active = false` and apply as the phase-0 role.
2. **Re-attach any detached SCP** (Step 3) and confirm the guardrail is back via a fresh `aws-organization` apply.
3. **Check the `org-guard-alerts` emails** for the session window. That topic is in us-east-1 of the management account and is owned by `aws-organization`. Account for every alert: disabled delegated admins or trusted access, deregistered delegated admins, and org-trail selector or tag changes. Re-enable anything that was turned off by re-applying `aws-security`. Confirm `enable_security_service_teardown` is `false` on `aws-organization`.
4. **Pull the audit trail** from the org CloudTrail in the Log Archive account for the break-glass session window; verify only authorized actions were taken.
5. File the post-incident review within 24 hours. If unauthorized actions are found, escalate as a security incident (see [`aws-incident-response.md`](aws-incident-response.md)).

---

## See also

- [AWS Landing Zone](../architecture/aws-landing-zone.md#root-access-management--break-glass) — guardrails and root-access management.
- [AWS Incident Response](aws-incident-response.md) — quarantine and forensics flow.
- [GCP Break-Glass](break-glass.md) — the GCP-side procedure this mirrors.
