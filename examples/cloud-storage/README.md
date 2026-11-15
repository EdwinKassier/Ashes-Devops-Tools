# Cloud Storage Example

Creates two application data buckets with CMEK encryption plus the module's fixed
infrastructure buckets (access logs, audit logs). All buckets enforce uniform
bucket-level access and public-access prevention.

## What this creates

| Resource | Notes |
|----------|-------|
| `raw-ingest` bucket | CMEK-encrypted, versioning enabled, 7-day soft delete. No expiry rule: set `retention_days` on the entry to add one |
| `processed` bucket | CMEK-encrypted, versioning enabled, 7-day soft delete |
| Logs bucket (`<project_id>-logs`) | Receives the usage logs of the data buckets; also meant as a destination for an audit log sink (output `logs_bucket_name`). Objects deleted after `log_retention_days` |
| Access-logs bucket (`<project_id>-bucket-access-logs`) | Receives the usage logs of the logs bucket. Objects deleted after `log_retention_days` |
| Bucket IAM (`roles/storage.objectViewer`) | Granted to `allowed_members` on every data bucket (read only; additive) |

## Prerequisites

- A GCP project with the **Cloud Storage** and **Cloud KMS** APIs enabled.
- A KMS key in the same region as the buckets. Use the `examples/kms` example
  to create one, then copy its `app_key_id` output.
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
| `data_buckets` | Add/remove buckets; set `force_destroy = true` in non-prod; `retention_days` adds an object expiry rule; `soft_delete_retention_seconds` (default 7 days, `0` = off) |
| `log_retention_days` | Days the two log buckets keep objects. The module default is 90; this example sets 30. Increase for compliance |
| `allowed_members` | Service accounts, groups, or users that need read access (`roles/storage.objectViewer`). Grant write roles outside the module |
