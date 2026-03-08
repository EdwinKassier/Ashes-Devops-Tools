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

<!-- BEGIN_TF_DOCS -->
KMS Module - Customer-Managed Encryption Keys
Provides Keyrings and CryptoKeys for CMEK compliance

## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	keyring_name = 
	project_id = 
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0, < 2.0.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | ~> 6.0 |



## Resources

The following resources are created:


- resource.google_kms_crypto_key.keys (modules/governance/kms/main.tf#L14)
- resource.google_kms_crypto_key_iam_member.key_iam (modules/governance/kms/main.tf#L36)
- resource.google_kms_key_ring.keyring (modules/governance/kms/main.tf#L7)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_keyring_name"></a> [keyring\_name](#input\_keyring\_name) | Name of the KMS Keyring | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | Project ID where the Keyring will be created | `string` | n/a | yes |
| <a name="input_keys"></a> [keys](#input\_keys) | Map of CryptoKeys to create | <pre>map(object({<br/>    rotation_period      = optional(string, "7776000s") # 90 days<br/>    purpose              = optional(string, "ENCRYPT_DECRYPT")<br/>    algorithm            = optional(string, "GOOGLE_SYMMETRIC_ENCRYPTION")<br/>    protection_level     = optional(string, "SOFTWARE")<br/>    labels               = optional(map(string), {})<br/>    encrypter_decrypters = optional(list(string), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels for all keys | `map(string)` | `{}` | no |
| <a name="input_location"></a> [location](#input\_location) | Location for the Keyring (region or 'global') | `string` | `"global"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_key_ids"></a> [key\_ids](#output\_key\_ids) | Map of CryptoKey IDs |
| <a name="output_key_names"></a> [key\_names](#output\_key\_names) | Map of CryptoKey names (for use in resource configs) |
| <a name="output_keyring_id"></a> [keyring\_id](#output\_keyring\_id) | ID of the KMS Keyring |
| <a name="output_keyring_name"></a> [keyring\_name](#output\_keyring\_name) | Name of the KMS Keyring |
<!-- END_TF_DOCS -->