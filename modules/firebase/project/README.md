<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	project_id = 
	
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0, < 2.0.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | ~> 6.0 |
| <a name="requirement_google-beta"></a> [google-beta](#requirement\_google-beta) | ~> 6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 6.50.0 |
| <a name="provider_google-beta"></a> [google-beta](#provider\_google-beta) | 7.14.1 |



## Resources

The following resources are created:


- resource.google-beta_google_apikeys_key.apple (modules/firebase/project/main.tf#L47)
- resource.google-beta_google_firebase_android_app.default (modules/firebase/project/main.tf#L66)
- resource.google-beta_google_firebase_apple_app.default (modules/firebase/project/main.tf#L34)
- resource.google-beta_google_firebase_project.default (modules/firebase/project/main.tf#L3)
- resource.google-beta_google_firebase_web_app.default (modules/firebase/project/main.tf#L79)
- resource.google-beta_google_storage_bucket.firebase_web_config (modules/firebase/project/main.tf#L132)
- resource.google-beta_google_storage_bucket.firebase_web_config_access_logs (modules/firebase/project/main.tf#L94)
- resource.google-beta_google_storage_bucket_iam_member.firebase_web_config_access_log_writer (modules/firebase/project/main.tf#L123)
- resource.google-beta_google_storage_bucket_object.firebase_config (modules/firebase/project/main.tf#L168)
- resource.google_project_service.firebase (modules/firebase/project/main.tf#L9)
- resource.google_project_service.firestore (modules/firebase/project/main.tf#L17)
- resource.google_project_service.identitytoolkit (modules/firebase/project/main.tf#L25)
- data source.google-beta_google_firebase_web_app_config.default (modules/firebase/project/main.tf#L88)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The GCP project ID | `string` | n/a | yes |
| <a name="input_android_display_name"></a> [android\_display\_name](#input\_android\_display\_name) | Display name for the Android app | `string` | `""` | no |
| <a name="input_android_package_name"></a> [android\_package\_name](#input\_android\_package\_name) | Package name for the Android app | `string` | `""` | no |
| <a name="input_android_sha1_hashes"></a> [android\_sha1\_hashes](#input\_android\_sha1\_hashes) | List of SHA-1 hashes for the Android app | `list(string)` | `[]` | no |
| <a name="input_android_sha256_hashes"></a> [android\_sha256\_hashes](#input\_android\_sha256\_hashes) | List of SHA-256 hashes for the Android app | `list(string)` | `[]` | no |
| <a name="input_apple_app_store_id"></a> [apple\_app\_store\_id](#input\_apple\_app\_store\_id) | App Store ID for the Apple app | `string` | `""` | no |
| <a name="input_apple_bundle_id"></a> [apple\_bundle\_id](#input\_apple\_bundle\_id) | Bundle ID for the Apple app | `string` | `""` | no |
| <a name="input_apple_display_name"></a> [apple\_display\_name](#input\_apple\_display\_name) | Display name for the Apple app | `string` | `""` | no |
| <a name="input_apple_team_id"></a> [apple\_team\_id](#input\_apple\_team\_id) | Apple Team ID for the Apple app | `string` | `""` | no |
| <a name="input_kms_key_name"></a> [kms\_key\_name](#input\_kms\_key\_name) | Optional customer-managed KMS key used for the Firebase web config bucket | `string` | `null` | no |
| <a name="input_region"></a> [region](#input\_region) | The GCP region | `string` | `"us-central1"` | no |
| <a name="input_web_display_name"></a> [web\_display\_name](#input\_web\_display\_name) | Display name for the web app | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_android_app_id"></a> [android\_app\_id](#output\_android\_app\_id) | The Android app ID |
| <a name="output_apple_api_key_id"></a> [apple\_api\_key\_id](#output\_apple\_api\_key\_id) | The Apple API key ID |
| <a name="output_apple_app_id"></a> [apple\_app\_id](#output\_apple\_app\_id) | The Apple app ID |
| <a name="output_firebase_config"></a> [firebase\_config](#output\_firebase\_config) | The Firebase web config |
| <a name="output_firebase_config_bucket"></a> [firebase\_config\_bucket](#output\_firebase\_config\_bucket) | The GCS bucket containing the Firebase config |
| <a name="output_project_id"></a> [project\_id](#output\_project\_id) | The Firebase project ID |
| <a name="output_web_app_id"></a> [web\_app\_id](#output\_web\_app\_id) | The Web app ID |
<!-- END_TF_DOCS -->
