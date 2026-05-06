# Runbook: KMS Key Rotation

**When to use:** Rotating a CMEK key version on schedule, after a suspected key compromise, or as part of a compliance audit.

**Time:** 15–45 minutes depending on the number of encrypted resources.  
**Risk:** Medium — a failed rotation can render encrypted data temporarily inaccessible.  
**Prerequisites:** You have `roles/cloudkms.admin` on the key's project.

---

## Background

GCP supports automatic key rotation (configured via `rotation_period` in the KMS module). When a new key version is created by rotation, GCP automatically uses the new primary version for all **new** encrypt operations. Existing data encrypted with the old version remains readable — GCP transparently decrypts using the version that encrypted the data.

This means:
- **Automatic rotation** (set `rotation_period`) is safe and requires no data re-encryption.
- **Manual rotation** (forced key version change) may require re-encryption if you want to eliminate the old version.
- **Key destruction** is permanent and must never be done while encrypted data exists.

---

## Automatic Rotation (preferred)

The `modules/governance/kms` module configures `rotation_period`. When Terraform manages the key, rotation is handled by GCP automatically. No operator action is needed.

To verify the current rotation policy:

```bash
gcloud kms keys describe KEY_NAME \
  --keyring=KEYRING_NAME \
  --location=LOCATION \
  --project=PROJECT_ID \
  --format="value(rotationPeriod, nextRotationTime)"
```

To change the rotation period via Terraform, update `var.rotation_period` in the module call and apply:

```bash
terraform -chdir=envs/organization plan -target=module.cmek
terraform -chdir=envs/organization apply -target=module.cmek
```

---

## Manual Key Version Rotation

If you need to force an immediate rotation (e.g., after suspected key material exposure):

### Step 1 — Create a new key version

```bash
gcloud kms keys versions create \
  --key=KEY_NAME \
  --keyring=KEYRING_NAME \
  --location=LOCATION \
  --project=PROJECT_ID
```

Note the new version number in the output (e.g., `3`).

### Step 2 — Set the new version as primary

```bash
gcloud kms keys update KEY_NAME \
  --keyring=KEYRING_NAME \
  --location=LOCATION \
  --project=PROJECT_ID \
  --primary-version=3
```

All new encrypt operations now use version 3.

### Step 3 — Re-encrypt resources (if retiring the old version)

> **Only required if you intend to disable or destroy the old version.**

For Cloud Storage buckets, you must re-write objects to trigger re-encryption:

```bash
# Re-encrypt a single bucket
gsutil rewrite -k gs://BUCKET_NAME/**
```

For BigQuery datasets, re-encryption happens automatically on the next write. Query the dataset to verify access is maintained.

For Cloud SQL, key rotation is transparent — existing data is re-encrypted on the next disk write cycle.

### Step 4 — Disable the old version

After confirming all data is re-encrypted:

```bash
gcloud kms keys versions disable OLD_VERSION \
  --key=KEY_NAME \
  --keyring=KEYRING_NAME \
  --location=LOCATION \
  --project=PROJECT_ID
```

Wait at least 24 hours and verify no decrypt errors appear in Cloud Audit Logs before proceeding to destroy.

### Step 5 — (Optional) Schedule old version for destruction

```bash
# Destruction has a mandatory 24-hour pending period
gcloud kms keys versions destroy OLD_VERSION \
  --key=KEY_NAME \
  --keyring=KEYRING_NAME \
  --location=LOCATION \
  --project=PROJECT_ID
```

> **Warning:** Key destruction is **permanent and irreversible**. Any data encrypted solely with the destroyed version will be permanently inaccessible. Only destroy a version after confirming all resources have been re-encrypted.

---

## Verify Audit Logs After Rotation

After any key rotation, confirm no decrypt errors surfaced:

```bash
gcloud logging read \
  'resource.type="cloudkms_cryptokey" AND severity>=WARNING' \
  --project=PROJECT_ID \
  --limit=20 \
  --format="table(timestamp, severity, textPayload)"
```

Zero `WARNING` or `ERROR` entries means the rotation is clean.

---

## Terraform State After Manual Rotation

If you manually created a new key version outside of Terraform, the Terraform state will show a drift on the `primary_version` attribute. Run:

```bash
terraform -chdir=envs/organization refresh -target=module.cmek
```

This updates the state to match the current GCP reality without making any resource changes.
