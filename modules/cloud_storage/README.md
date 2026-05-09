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
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.9 |
| <a name="requirement_google"></a> [google](#requirement\_google) | >= 6.0, < 8.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_google"></a> [google](#provider\_google) | 7.31.0 |



## Resources

The following resources are created:


- resource.google_storage_bucket.access_logs (modules/cloud_storage/main.tf#L2)
- resource.google_storage_bucket.data (modules/cloud_storage/main.tf#L70)
- resource.google_storage_bucket.logs (modules/cloud_storage/main.tf#L34)
- resource.google_storage_bucket_iam_member.access_log_writer (modules/cloud_storage/main.tf#L27)
- resource.google_storage_bucket_iam_member.log_writer (modules/cloud_storage/main.tf#L63)
- resource.google_storage_bucket_iam_member.private (modules/cloud_storage/main.tf#L114)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The ID of the project | `string` | n/a | yes |
| <a name="input_allowed_members"></a> [allowed\_members](#input\_allowed\_members) | List of members with objectViewer read access to all data\_buckets (e.g., ['user:user@example.com', 'group:admins@example.com', 'serviceAccount:sa@project.iam.gserviceaccount.com']) | `list(string)` | `[]` | no |
| <a name="input_data_buckets"></a> [data\_buckets](#input\_data\_buckets) | Map of logical key to data bucket configuration. Each entry creates one GCS bucket.<br/>The bucket name is: "<project\_id>-<name\_suffix>".<br/>Example:<br/>  data\_buckets = {<br/>    twitter\_data\_lake    = { name\_suffix = "twitter-data-lake" }<br/>    twitter\_dataflow\_meta = { name\_suffix = "twitter-dataflow-meta" }<br/>  } | <pre>map(object({<br/>    name_suffix   = string<br/>    force_destroy = optional(bool, false)<br/>    # Soft-delete retention in seconds. Set to 0 to disable soft-delete (useful in dev/test).<br/>    # Default 604800 = 7 days (GCS default).<br/>    soft_delete_retention_seconds = optional(number, 604800)<br/>    # Optional hard-delete lifecycle age in days. When set, objects are permanently deleted<br/>    # after this many days. Leave null for indefinite retention (default).<br/>    retention_days = optional(number, null)<br/>  }))</pre> | `{}` | no |
| <a name="input_kms_key_name"></a> [kms\_key\_name](#input\_kms\_key\_name) | Fully qualified KMS key name for bucket encryption.<br/>Format: projects/<project>/locations/<location>/keyRings/<keyring>/cryptoKeys/<key><br/>Leave null to use Google-managed encryption (GMEK). For compliance environments,<br/>always supply a CMEK key and ensure the GCS service account has<br/>roles/cloudkms.cryptoKeyEncrypterDecrypter on the key. | `string` | `null` | no |
| <a name="input_labels"></a> [labels](#input\_labels) | Labels to apply to all storage bucket resources in this module. | `map(string)` | `{}` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Number of days to retain logs in the logging bucket. Minimum 1 day. | `number` | `90` | no |
| <a name="input_region"></a> [region](#input\_region) | The region where resources will be created | `string` | `"us-central1"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_access_logs_bucket_name"></a> [access\_logs\_bucket\_name](#output\_access\_logs\_bucket\_name) | Name of the terminal access log bucket (used as log\_bucket for other buckets in this module) |
| <a name="output_bucket_names"></a> [bucket\_names](#output\_bucket\_names) | Map of data\_buckets key to bucket name for all data buckets in this module |
| <a name="output_bucket_self_links"></a> [bucket\_self\_links](#output\_bucket\_self\_links) | Map of data\_buckets key to self\_link for all data buckets in this module |
| <a name="output_logs_bucket_name"></a> [logs\_bucket\_name](#output\_logs\_bucket\_name) | Name of the audit logs bucket (used as a log sink destination) |
<!-- END_TF_DOCS -->