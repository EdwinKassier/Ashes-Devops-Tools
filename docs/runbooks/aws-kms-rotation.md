# Runbook: AWS KMS Key Rotation

**When to use:** Rotating a customer-managed KMS key (CMK) on schedule, after a suspected key compromise, or as part of a compliance audit. This is the AWS counterpart to the GCP [KMS rotation runbook](kms-rotation.md).

**Time:** 10–45 minutes depending on the number of encrypted resources.
**Risk:** Medium — automatic rotation is transparent, but a full key *replacement* (new CMK) can render encrypted data inaccessible if grants or re-encryption are mishandled.
**Prerequisites:** You hold key-administration (`kms:*`) on the CMK — in this landing zone that is the `key_admin_arn` principal configured on the key — and access to the account that owns it (for the log CMK, the Log-Archive account).

---

> **Prefer automatic rotation.** The CMKs in this landing zone rotate their backing key material automatically. On-demand and full-replacement procedures below exist for compromise and compliance scenarios only. All KMS API activity is captured by the org CloudTrail in the Log-Archive account.

---

## Background

The `modules/aws/data/kms-key` module creates a **single-Region, customer-managed CMK** with an alias, a key policy, and `enable_key_rotation = true`. Because rotation is on:

- AWS rotates the CMK's **backing key material** automatically. By default AWS does this **annually** (every 365 days).
- The **key ID, key ARN, and alias never change** across a rotation. Every consumer references the key by ARN or alias, so rotation needs **no rewiring** and **no re-encryption**.
- AWS retains **all older key-material versions** for as long as the CMK exists, and transparently decrypts each ciphertext with the version that encrypted it. Existing data stays readable.

This means:

- **Automatic rotation** (already enabled) is safe and requires no operator action or data re-encryption.
- **On-demand rotation** (`rotate-key-on-demand`) creates a new backing-material version immediately, still under the same key ID/ARN — also transparent.
- **Full key replacement** (a brand-new CMK behind the same alias) is the only path that requires grant migration and re-encryption, and is the only path that can make old data inaccessible.

Two properties of *this module* are worth knowing before you plan a change:

- `enable_key_rotation` is set to `true` in the module and is **not exposed as a variable** — rotation is always on and cannot be toggled off without editing the module.
- The module does **not** expose a rotation-period variable, so the CMKs use AWS's **default annual (365-day)** period. There is no `rotation_period_in_days` input to change; a shorter period would require a module change (see [Changing the rotation period](#changing-the-rotation-period)).

### Customer-managed vs AWS-managed keys

Only **customer-managed CMKs** — the ones this module creates — support on-demand rotation and configurable/inspectable rotation policy. **AWS-managed keys** (e.g. the default `aws/ebs`, `aws/secretsmanager`, `aws/sns` keys that a consumer falls back to when no CMK is supplied) rotate on a fixed AWS-controlled schedule that you cannot change or trigger. The procedures below apply to the customer-managed CMKs.

---

## Which keys this covers

The `kms-key` module is instantiated in `modules/aws/stages/security` and consumed across the security baseline:

| CMK (alias) | Owning account | Consumers |
|---|---|---|
| `log-archive` (`log_cmk`) | Log-Archive | Log-Archive S3 bucket, org CloudTrail (S3 log files), Security Lake |
| security-tooling (`sectool_cmk`) | Security tooling | SNS security-notifications topic, Secrets Manager, and other local service principals (`sns`, `ssm`, `cloudwatch`) |
| forensics (`forensics_cmk`) | Forensics | Encrypted forensic snapshots shared cross-account |

EBS default encryption is set per-Region to a supplied CMK by `modules/aws/governance/account-baseline` (`kms_key_arn`); when that input is empty the account keeps the AWS-managed `aws/ebs` key.

---

## Verify Rotation Status (start here)

Confirm automatic rotation is enabled and inspect the schedule.

**CLI:**

```bash
aws kms get-key-rotation-status --key-id alias/log-archive
```

A healthy CMK returns:

```json
{
  "KeyRotationEnabled": true,
  "RotationPeriodInDays": 365,
  "NextRotationDate": "2027-01-15T00:00:00+00:00"
}
```

`KeyRotationEnabled: true` on every CMK is the expected steady state (the module hard-sets it).

**Console:** KMS → Customer managed keys → select the key → **Key rotation** tab. "Automatically rotate this KMS key every year" should be enabled.

To list the material versions AWS has retained for a key:

```bash
aws kms list-key-rotations --key-id alias/log-archive
```

---

## Automatic Rotation (preferred)

Nothing to do. The module sets `enable_key_rotation = true`, so AWS rotates the backing material annually with no operator involvement and no impact on consumers — the key ID, ARN, and alias are unchanged, so CloudTrail, the Log-Archive bucket, SNS, Security Lake, and EBS default encryption all keep working against the same key reference.

### Changing the rotation period

The module does not expose a rotation-period input, so the CMKs use the default 365-day period. If a compliance standard requires a shorter period (AWS supports 90–2560 days), add a `rotation_period_in_days` argument to `aws_kms_key` in `modules/aws/data/kms-key/main.tf` (plumb it through as a variable), then plan/apply through the `aws-security` workspace:

```bash
terraform -chdir=envs/aws/security plan
terraform -chdir=envs/aws/security apply   # apply via Terraform Cloud, not locally
```

> Do not run `terraform apply` locally against the AWS roots — TFC executes the apply. See CLAUDE.md → State & Apply Rules.

---

## On-Demand Rotation

If you need to rotate the backing material **immediately** (e.g. after suspected exposure) without waiting for the annual cycle, and without replacing the key:

```bash
aws kms rotate-key-on-demand --key-id alias/log-archive
```

This creates a new backing-material version at once, under the **same key ID/ARN/alias**. It is transparent to every consumer — no re-encryption, no grant changes. On-demand rotation is supported only for customer-managed keys with rotation enabled (which is every CMK this module makes). AWS limits how many on-demand rotations a key may accumulate; if the call is rejected for that reason, plan a full key replacement instead.

Verify afterward:

```bash
aws kms list-key-rotations --key-id alias/log-archive   # new ROTATE_ON_DEMAND entry
aws kms get-key-rotation-status --key-id alias/log-archive
```

---

## Full Key Replacement (compromise or policy change)

Use this **only** when the key itself must change identity — a confirmed compromise of key administration, a required key-policy/grant redesign, or a mandate to retire the old key entirely. Unlike rotation, this changes the key ARN, so it **requires grant migration and re-encryption**.

The pattern is **alias re-point**: create a new CMK, move the alias to it, re-encrypt data, then retire the old key.

### Step 1 — Create the new CMK

Add a new `kms-key` module instance (new `alias` value, or a temporary alias) in `modules/aws/stages/security` and apply through the `aws-security` workspace. Keep `log_service_principals` / `service_principals` / `key_users` identical to the key you are replacing so the new key policy grants the same consumers.

### Step 2 — Re-point consumers to the new key

Update each consumer's `kms_key_arn` / `kms_key_id` input to the new key's ARN and apply. For the log CMK that is the Log-Archive bucket, org CloudTrail, and Security Lake; for the security-tooling CMK it is the SNS topic and Secrets Manager. New writes now use the new key.

> The **key policy is not inherited**: the new CMK only grants what its own `key_admin_arn`, `log_service_principals`, and `service_principals` list. Confirm CloudTrail's `EncryptionContext` and the `aws:SourceOrgID` conditions are present on the new key before switching CloudTrail over, or log delivery will fail closed. (See the CloudTrail-condition caveat in [`docs/known-gaps.md`](../known-gaps.md#open--validate-before-relying-on).)

### Step 3 — Re-encrypt existing data (only when retiring the old key)

Automatic and on-demand rotation never need this; **key replacement does** if you intend to delete the old CMK, because objects encrypted under the old ARN stay bound to it.

- **S3 Log-Archive bucket:** existing objects are re-encrypted only when rewritten. New CloudTrail/Security Lake deliveries land under the new key automatically; historical objects keep referencing the old key. **WORM caveat:** the Log-Archive bucket is created with S3 Object Lock in **COMPLIANCE** mode by default (`modules/aws/data/log-archive-bucket`, `object_lock_mode`), which is write-once-read-many against **all** principals including root. You **cannot** overwrite or re-encrypt locked objects until their retention lapses — so plan to **keep the old CMK alive** until every locked object's `retention_days` has expired. Do not schedule the old key for deletion while any object it encrypted is still under an active Object Lock retention.
- **EBS volumes:** volumes stay encrypted under the key active at creation. Re-encrypting means snapshot → copy-snapshot with the new key → restore. Changing `account-baseline`'s `kms_key_arn` only affects *newly* created volumes.
- **SNS / Secrets Manager:** re-encryption is transparent on the next publish/put; no manual rewrite needed.

### Step 4 — Retire the old CMK

Once every consumer is on the new key and all required data is re-encrypted (and, for the Log-Archive bucket, all Object-Lock retentions have lapsed):

```bash
# Scheduled deletion — irreversible after the waiting window
aws kms schedule-key-deletion --key-id <old-key-id> --pending-window-in-days 30
```

The module's `deletion_window_in_days` defaults to **30** (AWS permits 7–30). Prefer scheduling deletion over `disable-key`; if you only want to make the key unusable pending review, `aws kms disable-key --key-id <old-key-id>` is reversible.

> **Warning:** Key deletion is **permanent and irreversible** once the pending window elapses. Any data encrypted solely under the deleted CMK becomes permanently inaccessible. Cancel with `aws kms cancel-key-deletion` while the key is still `PendingDeletion` if you are unsure.

---

## Multi-Region Key Considerations

The `kms-key` module creates **single-Region keys only** — it does not set the `multi_region` argument on `aws_kms_key`, so every CMK here is Region-local, and its key material and rotations live in one Region.

Implications:

- Rotation status and on-demand rotation are per-key, per-Region. There is no replica key to keep in sync.
- The org CloudTrail is a **multi-Region trail** (`is_multi_region_trail = true`), but it delivers to a single S3 bucket encrypted with the single-Region log CMK — that is expected and supported.
- If a future requirement needs the *same* key usable in more than one Region (e.g. cross-Region DR for encrypted data), that is a **module enhancement** (create the primary with `multi_region = true` and add replica keys), not an operational step. Multi-Region primary keys rotate their shared material and propagate it to replicas automatically; single-Region keys like these do not participate in that.

---

## Verify After Rotation or Replacement

After any rotation or replacement, confirm consumers still encrypt/decrypt cleanly and no `AccessDenied`/`KMS` errors surfaced.

1. **Rotation status is healthy:**

   ```bash
   aws kms get-key-rotation-status --key-id alias/log-archive
   ```

2. **Consumers still work.** Confirm a fresh CloudTrail log file lands in the Log-Archive bucket, and that a test SNS publish on the security-notifications topic succeeds.

3. **No KMS-denied events in the org trail.** Query recent CloudTrail for KMS errors (from the Log-Archive / security-tooling account, or via Athena/Security Lake):

   ```bash
   aws cloudtrail lookup-events \
     --lookup-attributes AttributeKey=EventSource,AttributeValue=kms.amazonaws.com \
     --max-results 25 \
     --query 'Events[?contains(CloudTrailEvent, `errorCode`)].[EventName,EventTime]' \
     --output table
   ```

   Zero entries with an `errorCode` (e.g. `AccessDenied`, `KMSInvalidStateException`) over the change window means the rotation is clean.

---

## Terraform State After Out-of-Band Rotation

On-demand rotation (`rotate-key-on-demand`) and automatic rotation change only the **backing material**, not any Terraform-managed attribute — so they cause **no drift**. `enable_key_rotation` stays `true` and the key ID/ARN are unchanged; a subsequent plan is clean.

If you changed something Terraform *does* manage out of band (e.g. disabled a key, edited the key policy, or scheduled deletion), reconcile state through the `aws-security` workspace so Terraform and AWS agree:

```bash
terraform -chdir=envs/aws/security plan     # review drift; apply via TFC to converge
```

---

## See also

- [GCP KMS Key Rotation](kms-rotation.md) — the GCP-side procedure this mirrors.
- [AWS Landing Zone](../architecture/aws-landing-zone.md) — where the CMKs sit in the security baseline.
- [AWS Break-Glass](aws-break-glass.md) — emergency access if a key-policy change locks out administration.
