# KMS Example

Creates a Cloud KMS keyring with two CMEK keys: one for application data
encryption (e.g., Cloud Storage, BigQuery) and one for log encryption. Both keys
rotate automatically every 90 days.

## What this creates

| Resource | Notes |
|----------|-------|
| `google_kms_key_ring` | Keyring in the specified location |
| `app-data-key` | 90-day auto-rotation; `cryptoKeyEncrypterDecrypter` granted to app SA |
| `log-encryption-key` | 90-day auto-rotation; no IAM bindings (grant separately per use case) |

## Prerequisites

- A GCP project with the **Cloud KMS** API enabled (`cloudkms.googleapis.com`).
- The service accounts that will use the keys created before you apply (to add IAM bindings).

## Usage

```bash
# 1. Edit main.tf — set project_id, location, and the service account in iam_bindings
# 2. Initialise
terraform -chdir=examples/kms init

# 3. Plan
terraform -chdir=examples/kms plan

# 4. Apply
terraform -chdir=examples/kms apply

# 5. Use the output key ID when configuring other modules
terraform -chdir=examples/kms output app_key_id
```

## Using the key with Cloud Storage

```hcl
module "storage" {
  source       = "../../modules/cloud_storage"
  kms_key_name = module.kms.key_ids["app-data-key"]
  # ...
}
```

## Customisation

| Parameter | What to change |
|-----------|---------------|
| `rotation_period` | Must be `<= 7776000s` (90 days); increase only for non-sensitive data |
| `iam_bindings` | Add one entry per role × SA combination |
| `labels` | Add cost-centre, team, and environment labels |

## Key destruction protection

Keys with `prevent_destroy_keys = true` (the default) will cause `terraform destroy`
to fail. This is intentional — KMS key deletion is irreversible and requires a
30-day scheduled deletion window in GCP regardless of Terraform.
