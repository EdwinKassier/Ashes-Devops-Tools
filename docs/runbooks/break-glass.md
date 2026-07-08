# Runbook: Break-Glass Emergency Access

**When to use:** The Workload Identity Federation pipeline is broken, GitHub Actions cannot authenticate to GCP, and you need emergency access to investigate or remediate a production incident.

**Time:** 10–20 minutes to establish access.  
**Risk:** High — this procedure grants temporary elevated GCP access outside normal controls. All actions must be logged and the access revoked immediately after the incident.  
**Prerequisites:** You have `roles/resourcemanager.organizationAdmin` on the GCP organization, or a human approver who does.

---

> **This procedure bypasses WIF and CI controls. It must only be used during genuine incidents where normal access is unavailable.**
>
> All break-glass access is logged in Cloud Audit Logs under `cloudresourcemanager.googleapis.com` and `iam.googleapis.com`. Post-incident review must verify that no unauthorized actions were taken.

---

## When Is This Needed?

| Scenario | Use break-glass? |
|----------|-----------------|
| WIF pool deleted or misconfigured | Yes |
| GitHub Actions OIDC issuer down | Yes |
| Terraform SA deleted accidentally | Yes |
| Normal PR/CI workflow slow | No — use `make plan-*` locally |
| Reviewing logs | No — use `gcloud logging read` with personal ADC |

---

## Step 1 — Verify the Incident Requires Break-Glass

Before proceeding, confirm that:

1. The WIF pool still exists (it may just be misconfigured):

```bash
gcloud iam workload-identity-pools describe github-pool \
  --location=global \
  --project=ADMIN_PROJECT_ID
```

1. The Terraform SA still exists:

```bash
gcloud iam service-accounts describe terraform@ADMIN_PROJECT_ID.iam.gserviceaccount.com \
  --project=ADMIN_PROJECT_ID
```

If both exist, the issue may be a misconfigured attribute condition, not a missing resource. Try fixing the condition first — see [Troubleshoot WIF](#troubleshoot-wif) below.

---

## Step 2 — Request Human Approval

Break-glass access requires a second human to authorize. Document the following in your incident ticket before proceeding:

- **Incident description:** What is broken and what you intend to fix
- **Approver:** Name and GitHub handle of the person approving
- **Time box:** How long you expect to need access (max 4 hours)

---

## Step 3 — Create a Time-Boxed Service Account Key

```bash
# Create a temporary key (valid until manually deleted)
gcloud iam service-accounts keys create /tmp/break-glass-key.json \
  --iam-account=terraform@ADMIN_PROJECT_ID.iam.gserviceaccount.com \
  --project=ADMIN_PROJECT_ID

# Activate the key
export GOOGLE_APPLICATION_CREDENTIALS=/tmp/break-glass-key.json
```

> **Security:** The key file at `/tmp/break-glass-key.json` must not be committed, shared, or left on disk after the incident. Treat it as a one-time credential.

---

## Step 4 — Apply the Emergency Fix

With the break-glass credentials active, run the required Terraform operations:

```bash
terraform -chdir=envs/organization plan
terraform -chdir=envs/organization apply -target=module.bootstrap   # if WIF is broken
```

Or use `gcloud` commands directly if Terraform itself is the problem:

```bash
# Re-create a deleted WIF pool
gcloud iam workload-identity-pools create github-pool \
  --location=global \
  --display-name="GitHub Actions Pool" \
  --project=ADMIN_PROJECT_ID
```

---

## Step 5 — Verify Normal Access Is Restored

After the fix, trigger a GitHub Actions workflow to confirm WIF authentication works again:

1. Push an empty commit to a branch: `git commit --allow-empty -m "chore: verify WIF after break-glass"`
2. Open a PR and watch the `terraform-plan.yml` workflow
3. Confirm the workflow authenticates successfully

---

## Step 6 — Revoke Break-Glass Access (MANDATORY)

**This step must be completed before closing the incident.**

```bash
# List all keys on the Terraform SA
gcloud iam service-accounts keys list \
  --iam-account=terraform@ADMIN_PROJECT_ID.iam.gserviceaccount.com \
  --project=ADMIN_PROJECT_ID

# Delete the break-glass key by its KEY_ID
gcloud iam service-accounts keys delete KEY_ID \
  --iam-account=terraform@ADMIN_PROJECT_ID.iam.gserviceaccount.com \
  --project=ADMIN_PROJECT_ID

# Remove the local key file
rm /tmp/break-glass-key.json
unset GOOGLE_APPLICATION_CREDENTIALS
```

---

## Step 7 — Post-Incident Review

Within 24 hours, review all actions taken with the break-glass key:

```bash
gcloud logging read \
  'protoPayload.authenticationInfo.serviceAccountKeyName!=""' \
  --project=ADMIN_PROJECT_ID \
  --freshness=24h \
  --format="table(timestamp, protoPayload.methodName, protoPayload.authenticationInfo.principalEmail)"
```

Document the findings in the incident ticket and update this runbook if the break-glass procedure needs to change.

---

## Step 8 — If Unauthorized Access Is Discovered

If the post-incident review reveals actions that were **not authorized** by the named approver (e.g., unexpected resource deletions, IAM mutations, data exports), treat it as a security incident immediately:

### 8a — Contain (within the first hour)

```bash
# 1. Revoke ALL SA keys immediately (not just the break-glass key)
for KEY_ID in $(gcloud iam service-accounts keys list \
  --iam-account=terraform@ADMIN_PROJECT_ID.iam.gserviceaccount.com \
  --project=ADMIN_PROJECT_ID \
  --format="value(name)" \
  --filter="keyType=USER_MANAGED"); do
  gcloud iam service-accounts keys delete "$KEY_ID" \
    --iam-account=terraform@ADMIN_PROJECT_ID.iam.gserviceaccount.com \
    --project=ADMIN_PROJECT_ID --quiet
done

# 2. Disable the Terraform SA entirely until the scope of damage is known
gcloud iam service-accounts disable \
  terraform@ADMIN_PROJECT_ID.iam.gserviceaccount.com \
  --project=ADMIN_PROJECT_ID
```

> **Note:** Disabling the SA will break all Terraform runs until it is re-enabled. This is intentional — stopping further potential damage takes priority.

### 8b — Assess

Pull a full audit trail for the window the break-glass key was active, saving to a file for forensic review:

```bash
# Replace START and END with the key creation and deletion timestamps (from Step 7 output)
gcloud logging read \
  'protoPayload.authenticationInfo.serviceAccountKeyName!="" OR
   protoPayload.authenticationInfo.principalEmail="terraform@ADMIN_PROJECT_ID.iam.gserviceaccount.com"' \
  --project=ADMIN_PROJECT_ID \
  --freshness=72h \
  --format=json \
  > /tmp/incident-audit-$(date +%Y%m%d).json
```

Check specifically for:

- `SetIamPolicy` calls (IAM mutations)
- `DeleteBucket`, `DeleteDataset`, `DeleteObject` (data destruction)
- Any project outside the expected scope of the change

### 8c — Notify

1. **Immediately notify** the approver named in Step 2 and your security team.
2. If GCP resources were mutated beyond the authorized scope, open a [GCP Security incident](https://cloud.google.com/support/docs/issue-trackers).
3. File an internal postmortem within 48 hours covering: timeline, root cause, impact, and remediation steps taken.

### 8d — Remediate

After the investigation is complete:

```bash
# Re-enable the Terraform SA only after confirming scope and reverting unauthorized changes
gcloud iam service-accounts enable \
  terraform@ADMIN_PROJECT_ID.iam.gserviceaccount.com \
  --project=ADMIN_PROJECT_ID
```

Review and tighten the break-glass procedure based on findings — in particular:

- Was the approver verification step followed?
- Was the time box enforced?
- Should break-glass access require a separate short-lived SA with narrower permissions?

---

## Troubleshoot WIF

If the WIF pool and SA exist but authentication fails, the issue is usually the attribute condition.

Check the condition on the provider:

```bash
gcloud iam workload-identity-pools providers describe github \
  --workload-identity-pool=github-pool \
  --location=global \
  --project=ADMIN_PROJECT_ID \
  --format="yaml(attributeCondition, attributeMapping)"
```

Common issues:

| Symptom | Cause | Fix |
|---------|-------|-----|
| `PERMISSION_DENIED: attribute condition is not met` | Repo or branch does not match | Update `attribute.repository` or `attribute.ref` condition |
| `INVALID_ARGUMENT: token is expired` | GitHub OIDC token TTL exceeded | Retry the workflow — tokens are short-lived |
| `NOT_FOUND: workload identity pool not found` | Pool was deleted | Recreate via `terraform apply -target=module.bootstrap` |
