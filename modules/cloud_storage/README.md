<!-- BEGIN_TF_DOCS -->


## Usage

Basic usage of this module is as follows:

```hcl
module "example" {
	source = "<module-path>"

	# Required variables
	kms_key_name = 
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


- resource.google_storage_bucket.access_logs (modules/cloud_storage/main.tf#L2)
- resource.google_storage_bucket.logs (modules/cloud_storage/main.tf#L33)
- resource.google_storage_bucket.looker_data_backup (modules/cloud_storage/main.tf#L106)
- resource.google_storage_bucket.twitter_data_lake (modules/cloud_storage/main.tf#L68)
- resource.google_storage_bucket.twitter_dataflow_meta (modules/cloud_storage/main.tf#L87)
- resource.google_storage_bucket_iam_member.access_log_writer (modules/cloud_storage/main.tf#L26)
- resource.google_storage_bucket_iam_member.log_writer (modules/cloud_storage/main.tf#L61)
- resource.google_storage_bucket_iam_member.private (modules/cloud_storage/main.tf#L126)


## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_kms_key_name"></a> [kms\_key\_name](#input\_kms\_key\_name) | The name of the KMS key to use for encryption | `string` | n/a | yes |
| <a name="input_project_id"></a> [project\_id](#input\_project\_id) | The ID of the project | `string` | n/a | yes |
| <a name="input_allowed_members"></a> [allowed\_members](#input\_allowed\_members) | List of members with read access to the buckets (e.g., ['user:user@example.com', 'group:admins@example.com']) | `list(string)` | `[]` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Number of days to retain logs in the logging bucket | `number` | `90` | no |
| <a name="input_region"></a> [region](#input\_region) | The region where resources will be created | `string` | `"us-central1"` | no |

## Outputs

No outputs.
<!-- END_TF_DOCS -->