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

The Cloud Storage module lives at `modules/gcp/cloud-storage` (see
[`examples/cloud-storage`](../cloud-storage/)). Grant the project's Cloud
Storage service agent `roles/cloudkms.cryptoKeyEncrypterDecrypter` on the key
first, or bucket creation fails.

```hcl
module "storage" {
  source       = "../../modules/gcp/cloud-storage"
  kms_key_name = module.kms.key_ids["app-data-key"]
  # ...
}
```

## Customisation

| Parameter | What to change |
|-----------|---------------|
| `rotation_period` | Format `<N>s`. The module accepts `86400s` (1 day) to `31536000s` (365 days). Keep software keys at `7776000s` (90 days) or less (NIST SP 800-57 guidance); use a longer period only with a documented reason, for example HSM-backed keys |
| `iam_bindings` | Add one entry per role × SA combination |
| `labels` | Add cost-centre, team, and environment labels |

## Key destruction protection

The module hard-codes `lifecycle { prevent_destroy = true }` on every key (there
is no variable to turn it off), so `terraform destroy` or removing a key from
`keys` fails the plan. This is intentional: KMS key material cannot be
recovered once destroyed. Cloud KMS also never deletes a key outright; it
schedules the key versions for destruction after a waiting period, which
defaults to 30 days (this module does not change that default).
