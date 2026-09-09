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
gcloud iam service-accounts describe terraform-admin@ADMIN_PROJECT_ID.iam.gserviceaccount.com \
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

## Step 3 — Grant Time-Boxed KEYLESS Access

> **Why keyless:** the org baseline **enforces `iam.disableServiceAccountKeyCreation`
> org-wide** (`modules/gcp/stages/organization/main.tf`, and the `org-policy`
> recommended preset). Service-account **key creation is blocked by policy** — the old
> "create a key" flow would fail with a policy-violation error exactly when you need it.
> Use short-lived impersonation, which needs no key and works under the enforced policy.

### Primary path — impersonate the Terraform admin SA (keyless)

Grant the approved on-call operator's **human** identity the token-creator role on the
Terraform admin SA. It is scoped to that one SA and time-boxed by the revocation in
Step 6:

```bash
gcloud iam service-accounts add-iam-policy-binding \
  terraform-admin@ADMIN_PROJECT_ID.iam.gserviceaccount.com \
  --project=ADMIN_PROJECT_ID \
  --member="user:ONCALL_OPERATOR@example.com" \
  --role="roles/iam.serviceAccountTokenCreator"
```

Then run everything through impersonation — no key file is ever created:

```bash
# gcloud commands: impersonate directly
export CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT=terraform-admin@ADMIN_PROJECT_ID.iam.gserviceaccount.com

# Terraform: export a short-lived (1h) access token for the google provider
export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token \
  --impersonate-service-account=terraform-admin@ADMIN_PROJECT_ID.iam.gserviceaccount.com)"
```

### Fallback path — scoped org-policy exception (only if impersonation is impossible)

Use this **only** when the token-creator grant cannot be made (e.g. the IAM control
plane itself is broken) and a key is genuinely required. It temporarily lifts the
enforced policy **on the admin project only**; re-enforcing it in Step 6 is MANDATORY.

```bash
# 1. Scoped, project-level exception to the enforced org policy (admin project ONLY)
gcloud org-policies set-policy - <<'EOF'
name: projects/ADMIN_PROJECT_ID/policies/iam.disableServiceAccountKeyCreation
spec:
  rules:
    - enforce: false
EOF

# 2. Create the time-boxed key now that the exception is in place
gcloud iam service-accounts keys create /tmp/break-glass-key.json \
  --iam-account=terraform-admin@ADMIN_PROJECT_ID.iam.gserviceaccount.com \
  --project=ADMIN_PROJECT_ID
export GOOGLE_APPLICATION_CREDENTIALS=/tmp/break-glass-key.json
```

> **Security:** if you used the fallback, the key file at `/tmp/break-glass-key.json`
> must not be committed, shared, or left on disk after the incident, **and** you MUST
> re-enforce the org policy in Step 6. Treat it as a one-time credential.

---

## Step 4 — Apply the Emergency Fix

With the break-glass credentials active, run the required Terraform operations:

```bash
terraform -chdir=envs/gcp/organization plan
terraform -chdir=envs/gcp/organization apply -target=module.bootstrap   # if WIF is broken
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

### Primary path — revoke the keyless impersonation grant

```bash
# Remove the token-creator grant added in Step 3
gcloud iam service-accounts remove-iam-policy-binding \
  terraform-admin@ADMIN_PROJECT_ID.iam.gserviceaccount.com \
  --project=ADMIN_PROJECT_ID \
  --member="user:ONCALL_OPERATOR@example.com" \
  --role="roles/iam.serviceAccountTokenCreator"

# Drop the short-lived token / impersonation from this shell
unset GOOGLE_OAUTH_ACCESS_TOKEN CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT
```

### Fallback path — ONLY if you used the org-policy exception + key

```bash
# 1. Delete the break-glass key by its KEY_ID
gcloud iam service-accounts keys list \
  --iam-account=terraform-admin@ADMIN_PROJECT_ID.iam.gserviceaccount.com \
  --project=ADMIN_PROJECT_ID
gcloud iam service-accounts keys delete KEY_ID \
  --iam-account=terraform-admin@ADMIN_PROJECT_ID.iam.gserviceaccount.com \
  --project=ADMIN_PROJECT_ID
rm -f /tmp/break-glass-key.json
unset GOOGLE_APPLICATION_CREDENTIALS

# 2. MANDATORY: re-enforce the org policy exception you lifted in Step 3.
#    Deleting the project-level policy restores inheritance of the enforced org default.
gcloud org-policies delete iam.disableServiceAccountKeyCreation \
  --project=ADMIN_PROJECT_ID

# 3. Confirm the enforced policy is back in effect
gcloud org-policies describe iam.disableServiceAccountKeyCreation \
  --project=ADMIN_PROJECT_ID
```

---

## Step 7 — Post-Incident Review

Within 24 hours, review all actions taken during break-glass — both keyless
impersonation (the primary path) and, if used, the fallback key:

```bash
# All actions performed AS the Terraform admin SA (captures impersonation) plus any
# key-authenticated calls, in the incident window.
gcloud logging read \
  'protoPayload.authenticationInfo.principalEmail="terraform-admin@ADMIN_PROJECT_ID.iam.gserviceaccount.com"
   OR protoPayload.authenticationInfo.serviceAccountKeyName!=""
   OR protoPayload.authenticationInfo.serviceAccountDelegationInfo.firstPartyPrincipal.principalEmail:"terraform-admin"' \
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
  --iam-account=terraform-admin@ADMIN_PROJECT_ID.iam.gserviceaccount.com \
  --project=ADMIN_PROJECT_ID \
  --format="value(name)" \
  --filter="keyType=USER_MANAGED"); do
  gcloud iam service-accounts keys delete "$KEY_ID" \
    --iam-account=terraform-admin@ADMIN_PROJECT_ID.iam.gserviceaccount.com \
    --project=ADMIN_PROJECT_ID --quiet
done

# 2. Disable the Terraform SA entirely until the scope of damage is known
gcloud iam service-accounts disable \
  terraform-admin@ADMIN_PROJECT_ID.iam.gserviceaccount.com \
  --project=ADMIN_PROJECT_ID
```

> **Note:** Disabling the SA will break all Terraform runs until it is re-enabled. This is intentional — stopping further potential damage takes priority.

### 8b — Assess

Pull a full audit trail for the window the break-glass key was active, saving to a file for forensic review:

```bash
# Replace START and END with the key creation and deletion timestamps (from Step 7 output)
gcloud logging read \
  'protoPayload.authenticationInfo.serviceAccountKeyName!="" OR
   protoPayload.authenticationInfo.principalEmail="terraform-admin@ADMIN_PROJECT_ID.iam.gserviceaccount.com"' \
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
  terraform-admin@ADMIN_PROJECT_ID.iam.gserviceaccount.com \
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
