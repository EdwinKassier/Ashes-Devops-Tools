# Cloud Storage Example

Creates two application data buckets with CMEK encryption plus the module's fixed
infrastructure buckets (access logs, audit logs). All buckets enforce uniform
bucket-level access and public-access prevention.

## What this creates

| Resource | Notes |
|----------|-------|
| `raw-ingest` bucket | CMEK-encrypted, versioning enabled, lifecycle rules |
| `processed` bucket | CMEK-encrypted, versioning enabled |
| Access-logs bucket | Receives GCS access logs for all data buckets |
| Audit-logs bucket | Terraform state and audit log archive |
| Bucket IAM (objectAdmin) | Granted to `allowed_members` on every data bucket |

## Prerequisites

- A GCP project with the **Cloud Storage** and **Cloud KMS** APIs enabled.
- A KMS key in the same region as the buckets. Use the `examples/kms` example
  to create one, then copy its `key_id` output.
- The KMS crypto key must have the Cloud Storage service agent granted
  `roles/cloudkms.cryptoKeyEncrypterDecrypter`.

## Usage

```bash
# 1. Edit main.tf — set project_id, region, and kms_key_name
# 2. Initialise
terraform -chdir=examples/cloud-storage init

# 3. Plan
terraform -chdir=examples/cloud-storage plan

# 4. Apply
terraform -chdir=examples/cloud-storage apply
```

## Grant KMS access to the Storage service agent

Before applying, run:

```bash
PROJECT_NUMBER=$(gcloud projects describe <project-id> --format='value(projectNumber)')
gcloud kms keys add-iam-policy-binding <key-id> \
  --keyring=<keyring> \
  --location=<region> \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gs-project-accounts.iam.gserviceaccount.com" \
  --role="roles/cloudkms.cryptoKeyEncrypterDecrypter"
```

## Customisation

| Parameter | What to change |
|-----------|---------------|
| `data_buckets` | Add/remove buckets; set `force_destroy = true` in non-prod |
| `log_retention_days` | Increase for compliance (default 30) |
| `allowed_members` | Service accounts, groups, or users needing objectAdmin access |
