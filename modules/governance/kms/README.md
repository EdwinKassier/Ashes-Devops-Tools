# KMS (Key Management Service) Module

Creates Cloud KMS keyrings and crypto keys for customer-managed encryption (CMEK).

## Features

- Keyring and CryptoKey creation
- Automatic key rotation
- IAM bindings for encrypter/decrypter access
- HSM protection level support

## Usage

```hcl
module "kms" {
  source = "../../governance/kms"

  project_id   = "my-project"
  keyring_name = "my-keyring"
  location     = "europe-west1"

  keys = {
    "storage-key" = {
      rotation_period       = "7776000s"  # 90 days
      encrypter_decrypters  = ["serviceAccount:my-sa@project.iam.gserviceaccount.com"]
    }
    "bigquery-key" = {
      rotation_period = "7776000s"
      algorithm       = "GOOGLE_SYMMETRIC_ENCRYPTION"
    }
  }
}
```

## Inputs

| Name | Description | Type | Required |
|------|-------------|------|:--------:|
| project_id | Project ID | string | yes |
| keyring_name | Keyring name | string | yes |
| location | GCP region | string | yes |
| keys | Map of crypto keys | map(object) | yes |

## Outputs

| Name | Description |
|------|-------------|
| keyring_id | Keyring resource ID |
| key_ids | Map of crypto key IDs |
